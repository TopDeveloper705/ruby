#![allow(dead_code)]
#![allow(unused_variables)]
#![allow(unused_imports)]

use std::cell::Cell;
use std::fmt;
use std::convert::From;
use std::mem::take;
use crate::cruby::{VALUE};
use crate::virtualmem::{CodePtr};
use crate::asm::{CodeBlock, uimm_num_bits, imm_num_bits};
use crate::core::{Context, Type, TempMapping};

#[cfg(target_arch = "x86_64")]
use crate::backend::x86_64::*;

#[cfg(target_arch = "aarch64")]
use crate::backend::arm64::*;

pub const EC: Opnd = _EC;
pub const CFP: Opnd = _CFP;
pub const SP: Opnd = _SP;

pub const C_ARG_OPNDS: [Opnd; 6] = _C_ARG_OPNDS;
pub const C_RET_OPND: Opnd = _C_RET_OPND;

/// Instruction opcodes
#[derive(Copy, Clone, PartialEq, Eq, Debug)]
pub enum Op
{
    // Add a comment into the IR at the point that this instruction is added.
    // It won't have any impact on that actual compiled code.
    Comment,

    // Add a label into the IR at the point that this instruction is added.
    Label,

    // Mark a position in the generated code
    PosMarker,

    // Bake a string directly into the instruction stream.
    BakeString,

    // Add two operands together, and return the result as a new operand. This
    // operand can then be used as the operand on another instruction. It
    // accepts two operands, which can be of any type
    //
    // Under the hood when allocating registers, the IR will determine the most
    // efficient way to get these values into memory. For example, if both
    // operands are immediates, then it will load the first one into a register
    // first with a mov instruction and then add them together. If one of them
    // is a register, however, it will just perform a single add instruction.
    Add,

    // This is the same as the OP_ADD instruction, except for subtraction.
    Sub,

    // This is the same as the OP_ADD instruction, except that it performs the
    // binary AND operation.
    And,

    // This is the same as the OP_ADD instruction, except that it performs the
    // binary OR operation.
    Or,

    // This is the same as the OP_ADD instruction, except that it performs the
    // binary XOR operation.
    Xor,

    // Perform the NOT operation on an individual operand, and return the result
    // as a new operand. This operand can then be used as the operand on another
    // instruction.
    Not,

    /// Shift a value right by a certain amount (signed).
    RShift,

    /// Shift a value right by a certain amount (unsigned).
    URShift,

    /// Shift a value left by a certain amount.
    LShift,

    //
    // Low-level instructions
    //

    // A low-level instruction that loads a value into a register.
    Load,

    // A low-level instruction that loads a value into a register and
    // sign-extends it to a 64-bit value.
    LoadSExt,

    // Low-level instruction to store a value to memory.
    Store,

    // Load effective address
    Lea,

    // Load effective address relative to the current instruction pointer. It
    // accepts a single signed immediate operand.
    LeaLabel,

    // A low-level mov instruction. It accepts two operands.
    Mov,

    // Bitwise AND test instruction
    Test,

    // Compare two operands
    Cmp,

    // Unconditional jump to a branch target
    Jmp,

    // Unconditional jump which takes a reg/mem address operand
    JmpOpnd,

    // Low-level conditional jump instructions
    Jl,
    Jbe,
    Je,
    Jne,
    Jz,
    Jnz,
    Jo,

    // Conditional select instructions
    CSelZ,
    CSelNZ,
    CSelE,
    CSelNE,
    CSelL,
    CSelLE,
    CSelG,
    CSelGE,

    // Push and pop registers to/from the C stack
    CPush,
    CPop,
    CPopInto,

    // Push and pop all of the caller-save registers and the flags to/from the C
    // stack
    CPushAll,
    CPopAll,

    // C function call with N arguments (variadic)
    CCall,

    // C function return
    CRet,

    // Atomically increment a counter
    // Input: memory operand, increment value
    // Produces no output
    IncrCounter,

    // Trigger a debugger breakpoint
    Breakpoint,

    /// Set up the frame stack as necessary per the architecture.
    FrameSetup,

    /// Tear down the frame stack as necessary per the architecture.
    FrameTeardown,

    /// Take a specific register. Signal the register allocator to not use it.
    LiveReg,
}

// Memory operand base
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum MemBase
{
    Reg(u8),
    InsnOut(usize),
}

// Memory location
#[derive(Copy, Clone, PartialEq, Eq)]
pub struct Mem
{
    // Base register number or instruction index
    pub(super) base: MemBase,

    // Offset relative to the base pointer
    pub(super) disp: i32,

    // Size in bits
    pub(super) num_bits: u8,
}

impl fmt::Debug for Mem {
    fn fmt(&self, fmt: &mut fmt::Formatter) -> fmt::Result {
        write!(fmt, "Mem{}[{:?}", self.num_bits, self.base)?;
        if self.disp != 0 {
            let sign = if self.disp > 0 { '+' } else { '-' };
            write!(fmt, " {sign} {}", self.disp)?;
        }

        write!(fmt, "]")
    }
}

/// Operand to an IR instruction
#[derive(Clone, Copy, PartialEq, Eq)]
pub enum Opnd
{
    None,               // For insns with no output

    // Immediate Ruby value, may be GC'd, movable
    Value(VALUE),

    // Output of a preceding instruction in this block
    InsnOut{ idx: usize, num_bits: u8 },

    // Low-level operands, for lowering
    Imm(i64),           // Raw signed immediate
    UImm(u64),          // Raw unsigned immediate
    Mem(Mem),           // Memory location
    Reg(Reg),           // Machine register
}

impl fmt::Debug for Opnd {
    fn fmt(&self, fmt: &mut fmt::Formatter) -> fmt::Result {
        use Opnd::*;
        match self {
            Self::None => write!(fmt, "None"),
            Value(val) => write!(fmt, "Value({val:?})"),
            InsnOut { idx, num_bits } => write!(fmt, "Out{num_bits}({idx})"),
            Imm(signed) => write!(fmt, "{signed:x}_i64"),
            UImm(unsigned) => write!(fmt, "{unsigned:x}_u64"),
            // Say Mem and Reg only once
            Mem(mem) => write!(fmt, "{mem:?}"),
            Reg(reg) => write!(fmt, "{reg:?}"),
        }
    }
}

impl Opnd
{
    /// Convenience constructor for memory operands
    pub fn mem(num_bits: u8, base: Opnd, disp: i32) -> Self {
        match base {
            Opnd::Reg(base_reg) => {
                assert!(base_reg.num_bits == 64);
                Opnd::Mem(Mem {
                    base: MemBase::Reg(base_reg.reg_no),
                    disp: disp,
                    num_bits: num_bits,
                })
            },

            Opnd::InsnOut{idx, num_bits } => {
                assert!(num_bits == 64);
                Opnd::Mem(Mem {
                    base: MemBase::InsnOut(idx),
                    disp: disp,
                    num_bits: num_bits,
                })
            },

            _ => unreachable!("memory operand with non-register base")
        }
    }

    /// Constructor for constant pointer operand
    pub fn const_ptr(ptr: *const u8) -> Self {
        Opnd::UImm(ptr as u64)
    }

    pub fn is_some(&self) -> bool {
        match *self {
            Opnd::None => false,
            _ => true,
        }
    }

    /// Unwrap a register operand
    pub fn unwrap_reg(&self) -> Reg {
        match self {
            Opnd::Reg(reg) => *reg,
            _ => unreachable!("trying to unwrap {:?} into reg", self)
        }
    }

    /// Get the size in bits for register/memory operands
    pub fn rm_num_bits(&self) -> u8 {
        match *self {
            Opnd::Reg(reg) => reg.num_bits,
            Opnd::Mem(mem) => mem.num_bits,
            Opnd::InsnOut{ num_bits, .. } => num_bits,
            _ => unreachable!()
        }
    }

    /// Maps the indices from a previous list of instructions to a new list of
    /// instructions.
    pub fn map_index(self, indices: &Vec<usize>) -> Opnd {
        match self {
            Opnd::InsnOut { idx, num_bits } => {
                Opnd::InsnOut { idx: indices[idx], num_bits }
            }
            Opnd::Mem(Mem { base: MemBase::InsnOut(idx), disp, num_bits }) => {
                Opnd::Mem(Mem { base: MemBase::InsnOut(indices[idx]), disp, num_bits })
            },
            _ => self
        }
    }
}

impl From<usize> for Opnd {
    fn from(value: usize) -> Self {
        Opnd::UImm(value.try_into().unwrap())
    }
}

impl From<u64> for Opnd {
    fn from(value: u64) -> Self {
        Opnd::UImm(value.try_into().unwrap())
    }
}

impl From<i64> for Opnd {
    fn from(value: i64) -> Self {
        Opnd::Imm(value)
    }
}

impl From<i32> for Opnd {
    fn from(value: i32) -> Self {
        Opnd::Imm(value.try_into().unwrap())
    }
}

impl From<u32> for Opnd {
    fn from(value: u32) -> Self {
        Opnd::UImm(value as u64)
    }
}

impl From<VALUE> for Opnd {
    fn from(value: VALUE) -> Self {
        Opnd::Value(value)
    }
}

/// Branch target (something that we can jump to)
/// for branch instructions
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Target
{
    CodePtr(CodePtr),   // Pointer to a piece of YJIT-generated code (e.g. side-exit)
    FunPtr(*const u8),  // Pointer to a C function
    Label(usize),       // A label within the generated code
}

impl Target
{
    pub fn unwrap_fun_ptr(&self) -> *const u8 {
        match self {
            Target::FunPtr(ptr) => *ptr,
            _ => unreachable!("trying to unwrap {:?} into fun ptr", self)
        }
    }

    pub fn unwrap_label_idx(&self) -> usize {
        match self {
            Target::Label(idx) => *idx,
            _ => unreachable!("trying to unwrap {:?} into label", self)
        }
    }

    pub fn unwrap_code_ptr(&self) -> CodePtr {
        match self {
            Target::CodePtr(ptr) => *ptr,
            _ => unreachable!("trying to unwrap {:?} into code ptr", self)
        }
    }
}

impl From<CodePtr> for Target {
    fn from(code_ptr: CodePtr) -> Self {
        Target::CodePtr(code_ptr)
    }
}

type PosMarkerFn = Box<dyn Fn(CodePtr)>;

/// YJIT IR instruction
pub struct Insn
{
    // Opcode for the instruction
    pub(super) op: Op,

    // Optional string for comments and labels
    pub(super) text: Option<String>,

    // List of input operands/values
    pub(super) opnds: Vec<Opnd>,

    // Output operand for this instruction
    pub(super) out: Opnd,

    // List of branch targets (branch instructions only)
    pub(super) target: Option<Target>,

    // Callback to mark the position of this instruction
    // in the generated code
    pub(super) pos_marker: Option<PosMarkerFn>,
}

impl fmt::Debug for Insn {
    fn fmt(&self, fmt: &mut fmt::Formatter) -> fmt::Result {
        write!(fmt, "{:?}(", self.op)?;

        // Print list of operands
        let mut opnd_iter = self.opnds.iter();
        if let Some(first_opnd) = opnd_iter.next() {
            write!(fmt, "{first_opnd:?}")?;
        }
        for opnd in opnd_iter {
            write!(fmt, ", {opnd:?}")?;
        }
        write!(fmt, ")")?;

        // Print text, target, and pos if they are present
        if let Some(text) = &self.text {
            write!(fmt, " {text:?}")?
        }
        if let Some(target) = self.target {
            write!(fmt, " target={target:?}")?;
        }

        write!(fmt, " -> {:?}", self.out)
    }
}

/// Object into which we assemble instructions to be
/// optimized and lowered
pub struct Assembler
{
    pub(super) insns: Vec<Insn>,

    /// Parallel vec with insns
    /// Index of the last insn using the output of this insn
    pub(super) live_ranges: Vec<usize>,

    /// Names of labels
    pub(super) label_names: Vec<String>,
}

impl Assembler
{
    pub fn new() -> Self {
        Self::new_with_label_names(Vec::default())
    }

    pub fn new_with_label_names(label_names: Vec<String>) -> Self {
        Self {
            insns: Vec::default(),
            live_ranges: Vec::default(),
            label_names
        }
    }

    /// Append an instruction onto the current list of instructions.
    pub(super) fn push_insn(&mut self, mut insn: Insn) -> Opnd {
        // Index of this instruction
        let insn_idx = self.insns.len();

        // If we find any InsnOut from previous instructions, we're going to
        // update the live range of the previous instruction to point to this
        // one.
        for opnd in &insn.opnds {
            match opnd {
                Opnd::InsnOut{ idx, .. } => {
                    self.live_ranges[*idx] = insn_idx;
                }
                Opnd::Mem(Mem { base: MemBase::InsnOut(idx), .. }) => {
                    self.live_ranges[*idx] = insn_idx;
                }
                _ => {}
            }
        }

        let mut out_num_bits: u8 = 0;

        for opnd in &insn.opnds {
            match *opnd {
                Opnd::InsnOut{ num_bits, .. } |
                Opnd::Mem(Mem { num_bits, .. }) |
                Opnd::Reg(Reg { num_bits, .. }) => {
                    if out_num_bits == 0 {
                        out_num_bits = num_bits
                    }
                    else if out_num_bits != num_bits {
                        panic!("operands of incompatible sizes");
                    }
                }
                _ => {}
            }
        }

        if out_num_bits == 0 {
            out_num_bits = 64;
        }

        // Operand for the output of this instruction
        let out_opnd = Opnd::InsnOut{ idx: insn_idx, num_bits: out_num_bits };
        insn.out = out_opnd;

        self.insns.push(insn);
        self.live_ranges.push(insn_idx);

        // Return an operand for the output of this instruction
        out_opnd
    }

    /// Append an instruction to the list by creating a new instruction from the
    /// component parts given to this function.
    pub(super) fn push_insn_parts(
        &mut self,
        op: Op,
        opnds: Vec<Opnd>,
        target: Option<Target>,
        text: Option<String>,
        pos_marker: Option<PosMarkerFn>
    ) -> Opnd
    {
        self.push_insn(Insn {
            op,
            text,
            opnds,
            out: Opnd::None,
            target,
            pos_marker,
        })
    }

    /// Create a new label instance that we can jump to
    pub fn new_label(&mut self, name: &str) -> Target
    {
        assert!(!name.contains(" "), "use underscores in label names, not spaces");

        let label_idx = self.label_names.len();
        self.label_names.push(name.to_string());
        Target::Label(label_idx)
    }

    /// Add a label at the current position
    pub fn write_label(&mut self, label: Target)
    {
        assert!(label.unwrap_label_idx() < self.label_names.len());

        let insn = Insn {
            op: Op::Label,
            text: None,
            opnds: vec![],
            out: Opnd::None,
            target: Some(label),
            pos_marker: None,
        };
        self.insns.push(insn);
        self.live_ranges.push(self.insns.len());
    }

    /// Sets the out field on the various instructions that require allocated
    /// registers because their output is used as the operand on a subsequent
    /// instruction. This is our implementation of the linear scan algorithm.
    pub(super) fn alloc_regs(mut self, regs: Vec<Reg>) -> Assembler
    {
        //dbg!(&self);

        // First, create the pool of registers.
        let mut pool: u32 = 0;

        // Mutate the pool bitmap to indicate that the register at that index
        // has been allocated and is live.
        fn alloc_reg(pool: &mut u32, regs: &Vec<Reg>) -> Reg {
            for (index, reg) in regs.iter().enumerate() {
                if (*pool & (1 << index)) == 0 {
                    *pool |= 1 << index;
                    return *reg;
                }
            }

            unreachable!("Register spill not supported");
        }

        // Allocate a specific register
        fn take_reg(pool: &mut u32, regs: &Vec<Reg>, reg: &Reg) -> Reg {
            let reg_index = regs.iter().position(|elem| elem.reg_no == reg.reg_no);

            if let Some(reg_index) = reg_index {
                assert_eq!(*pool & (1 << reg_index), 0, "register already allocated");
                *pool |= 1 << reg_index;
            }

            return *reg;
        }

        // Mutate the pool bitmap to indicate that the given register is being
        // returned as it is no longer used by the instruction that previously
        // held it.
        fn dealloc_reg(pool: &mut u32, regs: &Vec<Reg>, reg: &Reg) {
            let reg_index = regs.iter().position(|elem| elem.reg_no == reg.reg_no);

            if let Some(reg_index) = reg_index {
                *pool &= !(1 << reg_index);
            }
        }

        let live_ranges: Vec<usize> = take(&mut self.live_ranges);
        let mut asm = Assembler::new_with_label_names(take(&mut self.label_names));
        let mut iterator = self.into_draining_iter();

        while let Some((index, insn)) = iterator.next_unmapped() {
            // Check if this is the last instruction that uses an operand that
            // spans more than one instruction. In that case, return the
            // allocated register to the pool.
            for opnd in &insn.opnds {
                match opnd {
                    Opnd::InsnOut{idx, .. } |
                    Opnd::Mem( Mem { base: MemBase::InsnOut(idx), .. }) => {
                        // Since we have an InsnOut, we know it spans more that one
                        // instruction.
                        let start_index = *idx;
                        assert!(start_index < index);

                        // We're going to check if this is the last instruction that
                        // uses this operand. If it is, we can return the allocated
                        // register to the pool.
                        if live_ranges[start_index] == index {
                            if let Opnd::Reg(reg) = asm.insns[start_index].out {
                                dealloc_reg(&mut pool, &regs, &reg);
                            } else {
                                unreachable!("no register allocated for insn {:?}", insn.op);
                            }
                        }
                    }

                    _ => {}
                }
            }

            // C return values need to be mapped to the C return register
            if insn.op == Op::CCall {
                assert_eq!(pool, 0, "register lives past C function call");
            }

            // If this instruction is used by another instruction,
            // we need to allocate a register to it
            let mut out_reg = Opnd::None;
            if live_ranges[index] != index {

                // C return values need to be mapped to the C return register
                if insn.op == Op::CCall {
                    out_reg = Opnd::Reg(take_reg(&mut pool, &regs, &C_RET_REG))
                }

                // If this instruction's first operand maps to a register and
                // this is the last use of the register, reuse the register
                // We do this to improve register allocation on x86
                // e.g. out  = add(reg0, reg1)
                //      reg0 = add(reg0, reg1)
                else if insn.opnds.len() > 0 {
                    if let Opnd::InsnOut{idx, ..} = insn.opnds[0] {
                        if live_ranges[idx] == index {
                            if let Opnd::Reg(reg) = asm.insns[idx].out {
                                out_reg = Opnd::Reg(take_reg(&mut pool, &regs, &reg))
                            }
                        }
                    }
                }

                // Allocate a new register for this instruction
                if out_reg == Opnd::None {
                    out_reg = if insn.op == Op::LiveReg {
                        // Allocate a specific register
                        let reg = insn.opnds[0].unwrap_reg();
                        Opnd::Reg(take_reg(&mut pool, &regs, &reg))
                    } else {
                        Opnd::Reg(alloc_reg(&mut pool, &regs))
                    }
                }
            }

            // Replace InsnOut operands by their corresponding register
            let reg_opnds: Vec<Opnd> = insn.opnds.into_iter().map(|opnd|
                match opnd {
                    Opnd::InsnOut{idx, ..} => asm.insns[idx].out,
                    Opnd::Mem(Mem { base: MemBase::InsnOut(idx), disp, num_bits }) => {
                        let out_reg = asm.insns[idx].out.unwrap_reg();
                        Opnd::Mem(Mem {
                            base: MemBase::Reg(out_reg.reg_no),
                            disp,
                            num_bits
                        })
                    }
                     _ => opnd,
                }
            ).collect();

            asm.push_insn_parts(insn.op, reg_opnds, insn.target, insn.text, insn.pos_marker);

            // Set the output register for this instruction
            let num_insns = asm.insns.len();
            let mut new_insn = &mut asm.insns[num_insns - 1];
            if let Opnd::Reg(reg) = out_reg {
                let num_out_bits = new_insn.out.rm_num_bits();
                out_reg = Opnd::Reg(reg.sub_reg(num_out_bits))
            }
            new_insn.out = out_reg;
        }

        assert_eq!(pool, 0, "Expected all registers to be returned to the pool");
        asm
    }

    /// Compile the instructions down to machine code
    /// NOTE: should compile return a list of block labels to enable
    ///       compiling multiple blocks at a time?
    pub fn compile(self, cb: &mut CodeBlock) -> Vec<u32>
    {
        let alloc_regs = Self::get_alloc_regs();
        self.compile_with_regs(cb, alloc_regs)
    }

    /// Compile with a limited number of registers
    pub fn compile_with_num_regs(self, cb: &mut CodeBlock, num_regs: usize) -> Vec<u32>
    {
        let mut alloc_regs = Self::get_alloc_regs();
        let alloc_regs = alloc_regs.drain(0..num_regs).collect();
        self.compile_with_regs(cb, alloc_regs)
    }

    /// Consume the assembler by creating a new draining iterator.
    pub fn into_draining_iter(self) -> AssemblerDrainingIterator {
        AssemblerDrainingIterator::new(self)
    }

    /// Consume the assembler by creating a new lookback iterator.
    pub fn into_lookback_iter(self) -> AssemblerLookbackIterator {
        AssemblerLookbackIterator::new(self)
    }
}

/// A struct that allows iterating through an assembler's instructions and
/// consuming them as it iterates.
pub struct AssemblerDrainingIterator {
    insns: std::vec::IntoIter<Insn>,
    index: usize,
    indices: Vec<usize>
}

impl AssemblerDrainingIterator {
    fn new(asm: Assembler) -> Self {
        Self {
            insns: asm.insns.into_iter(),
            index: 0,
            indices: Vec::default()
        }
    }

    /// When you're working with two lists of instructions, you need to make
    /// sure you do some bookkeeping to align the indices contained within the
    /// operands of the two lists.
    ///
    /// This function accepts the assembler that is being built and tracks the
    /// end of the current list of instructions in order to maintain that
    /// alignment.
    pub fn map_insn_index(&mut self, asm: &mut Assembler) {
        self.indices.push(asm.insns.len() - 1);
    }

    /// Map an operand by using this iterator's list of mapped indices.
    pub fn map_opnd(&self, opnd: Opnd) -> Opnd {
        opnd.map_index(&self.indices)
    }

    /// Returns the next instruction in the list with the indices corresponding
    /// to the next list of instructions.
    pub fn next_mapped(&mut self) -> Option<(usize, Insn)> {
        self.next_unmapped().map(|(index, insn)| {
            let opnds = insn.opnds.into_iter().map(|opnd| opnd.map_index(&self.indices)).collect();
            (index, Insn { opnds, ..insn })
        })
    }

    /// Returns the next instruction in the list with the indices corresponding
    /// to the previous list of instructions.
    pub fn next_unmapped(&mut self) -> Option<(usize, Insn)> {
        let index = self.index;
        self.index += 1;
        self.insns.next().map(|insn| (index, insn))
    }
}

/// A struct that allows iterating through references to an assembler's
/// instructions without consuming them.
pub struct AssemblerLookbackIterator {
    asm: Assembler,
    index: Cell<usize>
}

impl AssemblerLookbackIterator {
    fn new(asm: Assembler) -> Self {
        Self { asm, index: Cell::new(0) }
    }

    /// Fetches a reference to an instruction at a specific index.
    pub fn get(&self, index: usize) -> Option<&Insn> {
        self.asm.insns.get(index)
    }

    /// Fetches a reference to an instruction in the list relative to the
    /// current cursor location of this iterator.
    pub fn get_relative(&self, difference: i32) -> Option<&Insn> {
        let index: Result<i32, _> = self.index.get().try_into();
        let relative: Result<usize, _> = index.and_then(|value| (value + difference).try_into());
        relative.ok().and_then(|value| self.asm.insns.get(value))
    }

    /// Fetches the previous instruction relative to the current cursor location
    /// of this iterator.
    pub fn get_previous(&self) -> Option<&Insn> {
        self.get_relative(-1)
    }

    /// Fetches the next instruction relative to the current cursor location of
    /// this iterator.
    pub fn get_next(&self) -> Option<&Insn> {
        self.get_relative(1)
    }

    /// Returns the next instruction in the list with the indices corresponding
    /// to the previous list of instructions.
    pub fn next_unmapped(&self) -> Option<(usize, &Insn)> {
        let index = self.index.get();
        self.index.set(index + 1);
        self.asm.insns.get(index).map(|insn| (index, insn))
    }
}

impl fmt::Debug for Assembler {
    fn fmt(&self, fmt: &mut fmt::Formatter) -> fmt::Result {
        write!(fmt, "Assembler\n")?;

        for (idx, insn) in self.insns.iter().enumerate() {
            write!(fmt, "    {idx:03} {insn:?}\n")?;
        }

        Ok(())
    }
}

impl Assembler {
    #[must_use]
    pub fn add(&mut self, left: Opnd, right: Opnd) -> Opnd {
        self.push_insn(Insn { op: Op::Add, opnds: vec![left, right], out: Opnd::None, text: None, target: None, pos_marker: None })
    }

    #[must_use]
    pub fn and(&mut self, left: Opnd, right: Opnd) -> Opnd {
        self.push_insn(Insn { op: Op::And, opnds: vec![left, right], out: Opnd::None, text: None, target: None, pos_marker: None })
    }

    pub fn bake_string(&mut self, text: &str) {
        self.push_insn(Insn { op: Op::BakeString, opnds: vec![], out: Opnd::None, text: Some(text.to_string()), target: None, pos_marker: None });
    }

    pub fn breakpoint(&mut self) {
        self.push_insn(Insn { op: Op::Breakpoint, opnds: vec![], out: Opnd::None, text: None, target: None, pos_marker: None });
    }

    #[must_use]
    pub fn ccall(&mut self, fptr: *const u8, opnds: Vec<Opnd>) -> Opnd {
        self.push_insn(Insn { op: Op::CCall, opnds, out: Opnd::None, text: None, target: Some(Target::FunPtr(fptr)), pos_marker: None })
    }

    pub fn cmp(&mut self, left: Opnd, right: Opnd) {
        self.push_insn(Insn { op: Op::Cmp, opnds: vec![left, right], out: Opnd::None, text: None, target: None, pos_marker: None });
    }

    pub fn comment(&mut self, text: &str) {
        self.push_insn(Insn { op: Op::Comment, opnds: vec![], out: Opnd::None, text: Some(text.to_string()), target: None, pos_marker: None });
    }

    pub fn cpop(&mut self) -> Opnd {
        self.push_insn(Insn { op: Op::CPop, opnds: vec![], out: Opnd::None, text: None, target: None, pos_marker: None })
    }

    pub fn cpop_all(&mut self) {
        self.push_insn(Insn { op: Op::CPopAll, opnds: vec![], out: Opnd::None, text: None, target: None, pos_marker: None });
    }

    pub fn cpop_into(&mut self, opnd: Opnd) {
        self.push_insn(Insn { op: Op::CPopInto, opnds: vec![opnd], out: Opnd::None, text: None, target: None, pos_marker: None });
    }

    pub fn cpush(&mut self, opnd: Opnd) {
        self.push_insn(Insn { op: Op::CPush, opnds: vec![opnd], out: Opnd::None, text: None, target: None, pos_marker: None });
    }

    pub fn cpush_all(&mut self) {
        self.push_insn(Insn { op: Op::CPushAll, opnds: vec![], out: Opnd::None, text: None, target: None, pos_marker: None });
    }

    pub fn cret(&mut self, opnd: Opnd) {
        self.push_insn(Insn { op: Op::CRet, opnds: vec![opnd], out: Opnd::None, text: None, target: None, pos_marker: None });
    }

    #[must_use]
    pub fn csel_e(&mut self, truthy: Opnd, falsy: Opnd) -> Opnd {
        self.push_insn(Insn { op: Op::CSelE, opnds: vec![truthy, falsy], out: Opnd::None, text: None, target: None, pos_marker: None })
    }

    #[must_use]
    pub fn csel_g(&mut self, truthy: Opnd, falsy: Opnd) -> Opnd {
        self.push_insn(Insn { op: Op::CSelG, opnds: vec![truthy, falsy], out: Opnd::None, text: None, target: None, pos_marker: None })
    }

    #[must_use]
    pub fn csel_ge(&mut self, truthy: Opnd, falsy: Opnd) -> Opnd {
        self.push_insn(Insn { op: Op::CSelGE, opnds: vec![truthy, falsy], out: Opnd::None, text: None, target: None, pos_marker: None })
    }

    #[must_use]
    pub fn csel_l(&mut self, truthy: Opnd, falsy: Opnd) -> Opnd {
        self.push_insn(Insn { op: Op::CSelL, opnds: vec![truthy, falsy], out: Opnd::None, text: None, target: None, pos_marker: None })
    }

    #[must_use]
    pub fn csel_le(&mut self, truthy: Opnd, falsy: Opnd) -> Opnd {
        self.push_insn(Insn { op: Op::CSelLE, opnds: vec![truthy, falsy], out: Opnd::None, text: None, target: None, pos_marker: None })
    }

    #[must_use]
    pub fn csel_ne(&mut self, truthy: Opnd, falsy: Opnd) -> Opnd {
        self.push_insn(Insn { op: Op::CSelNE, opnds: vec![truthy, falsy], out: Opnd::None, text: None, target: None, pos_marker: None })
    }

    #[must_use]
    pub fn csel_nz(&mut self, truthy: Opnd, falsy: Opnd) -> Opnd {
        self.push_insn(Insn { op: Op::CSelNZ, opnds: vec![truthy, falsy], out: Opnd::None, text: None, target: None, pos_marker: None })
    }

    #[must_use]
    pub fn csel_z(&mut self, truthy: Opnd, falsy: Opnd) -> Opnd {
        self.push_insn(Insn { op: Op::CSelZ, opnds: vec![truthy, falsy], out: Opnd::None, text: None, target: None, pos_marker: None })
    }

    pub fn frame_setup(&mut self) {
        self.push_insn(Insn { op: Op::FrameSetup, opnds: vec![], out: Opnd::None, text: None, target: None, pos_marker: None });
    }

    pub fn frame_teardown(&mut self) {
        self.push_insn(Insn { op: Op::FrameTeardown, opnds: vec![], out: Opnd::None, text: None, target: None, pos_marker: None });
    }

    pub fn incr_counter(&mut self, mem: Opnd, value: Opnd) {
        self.push_insn(Insn { op: Op::IncrCounter, opnds: vec![mem, value], out: Opnd::None, text: None, target: None, pos_marker: None });
    }

    pub fn jbe(&mut self, target: Target) {
        self.push_insn(Insn { op: Op::Jbe, opnds: vec![], out: Opnd::None, text: None, target: Some(target), pos_marker: None });
    }

    pub fn je(&mut self, target: Target) {
        self.push_insn(Insn { op: Op::Je, opnds: vec![], out: Opnd::None, text: None, target: Some(target), pos_marker: None });
    }

    pub fn jl(&mut self, target: Target) {
        self.push_insn(Insn { op: Op::Jl, opnds: vec![], out: Opnd::None, text: None, target: Some(target), pos_marker: None });
    }

    pub fn jmp(&mut self, target: Target) {
        self.push_insn(Insn { op: Op::Jmp, opnds: vec![], out: Opnd::None, text: None, target: Some(target), pos_marker: None });
    }

    pub fn jmp_opnd(&mut self, opnd: Opnd) {
        self.push_insn(Insn { op: Op::JmpOpnd, opnds: vec![opnd], out: Opnd::None, text: None, target: None, pos_marker: None });
    }

    pub fn jne(&mut self, target: Target) {
        self.push_insn(Insn { op: Op::Jne, opnds: vec![], out: Opnd::None, text: None, target: Some(target), pos_marker: None });
    }

    pub fn jnz(&mut self, target: Target) {
        self.push_insn(Insn { op: Op::Jnz, opnds: vec![], out: Opnd::None, text: None, target: Some(target), pos_marker: None });
    }

    pub fn jo(&mut self, target: Target) {
        self.push_insn(Insn { op: Op::Jo, opnds: vec![], out: Opnd::None, text: None, target: Some(target), pos_marker: None });
    }

    pub fn jz(&mut self, target: Target) {
        self.push_insn(Insn { op: Op::Jz, opnds: vec![], out: Opnd::None, text: None, target: Some(target), pos_marker: None });
    }

    #[must_use]
    pub fn lea(&mut self, opnd: Opnd) -> Opnd {
        self.push_insn(Insn { op: Op::Lea, opnds: vec![opnd], out: Opnd::None, text: None, target: None, pos_marker: None })
    }

    #[must_use]
    pub fn lea_label(&mut self, target: Target) -> Opnd {
        self.push_insn(Insn { op: Op::LeaLabel, opnds: vec![], out: Opnd::None, text: None, target: Some(target), pos_marker: None })
    }

    #[must_use]
    pub fn live_reg_opnd(&mut self, opnd: Opnd) -> Opnd {
        self.push_insn(Insn { op: Op::LiveReg, opnds: vec![opnd], out: Opnd::None, text: None, target: None, pos_marker: None })
    }

    #[must_use]
    pub fn load(&mut self, opnd: Opnd) -> Opnd {
        self.push_insn(Insn { op: Op::Load, opnds: vec![opnd], out: Opnd::None, text: None, target: None, pos_marker: None })
    }

    #[must_use]
    pub fn load_sext(&mut self, opnd: Opnd) -> Opnd {
        self.push_insn(Insn { op: Op::LoadSExt, opnds: vec![opnd], out: Opnd::None, text: None, target: None, pos_marker: None })
    }

    #[must_use]
    pub fn lshift(&mut self, opnd: Opnd, shift: Opnd) -> Opnd {
        self.push_insn(Insn { op: Op::LShift, opnds: vec![opnd, shift], out: Opnd::None, text: None, target: None, pos_marker: None })
    }

    pub fn mov(&mut self, dest: Opnd, src: Opnd) {
        self.push_insn(Insn { op: Op::Mov, opnds: vec![dest, src], out: Opnd::None, text: None, target: None, pos_marker: None });
    }

    #[must_use]
    pub fn not(&mut self, opnd: Opnd) -> Opnd {
        self.push_insn(Insn { op: Op::Not, opnds: vec![opnd], out: Opnd::None, text: None, target: None, pos_marker: None })
    }

    #[must_use]
    pub fn or(&mut self, left: Opnd, right: Opnd) -> Opnd {
        self.push_insn(Insn { op: Op::Or, opnds: vec![left, right], out: Opnd::None, text: None, target: None, pos_marker: None })
    }

    //pub fn pos_marker<F: FnMut(CodePtr)>(&mut self, marker_fn: F)
    pub fn pos_marker(&mut self, marker_fn: impl Fn(CodePtr) + 'static) {
        self.push_insn(Insn { op: Op::PosMarker, opnds: vec![], out: Opnd::None, text: None, target: None, pos_marker: Some(Box::new(marker_fn)) });
    }

    #[must_use]
    pub fn rshift(&mut self, opnd: Opnd, shift: Opnd) -> Opnd {
        self.push_insn(Insn { op: Op::RShift, opnds: vec![opnd, shift], out: Opnd::None, text: None, target: None, pos_marker: None })
    }

    pub fn store(&mut self, dest: Opnd, src: Opnd) {
        self.push_insn(Insn { op: Op::Store, opnds: vec![dest, src], out: Opnd::None, text: None, target: None, pos_marker: None });
    }

    #[must_use]
    pub fn sub(&mut self, left: Opnd, right: Opnd) -> Opnd {
        self.push_insn(Insn { op: Op::Sub, opnds: vec![left, right], out: Opnd::None, text: None, target: None, pos_marker: None })
    }

    pub fn test(&mut self, left: Opnd, right: Opnd) {
        self.push_insn(Insn { op: Op::Test, opnds: vec![left, right], out: Opnd::None, text: None, target: None, pos_marker: None });
    }

    #[must_use]
    pub fn urshift(&mut self, opnd: Opnd, shift: Opnd) -> Opnd {
        self.push_insn(Insn { op: Op::URShift, opnds: vec![opnd, shift], out: Opnd::None, text: None, target: None, pos_marker: None })
    }

    #[must_use]
    pub fn xor(&mut self, left: Opnd, right: Opnd) -> Opnd {
        self.push_insn(Insn { op: Op::Xor, opnds: vec![left, right], out: Opnd::None, text: None, target: None, pos_marker: None })
    }
}
