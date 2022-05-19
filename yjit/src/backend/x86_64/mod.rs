#![allow(dead_code)]
#![allow(unused_variables)]
#![allow(unused_imports)]

use crate::asm::{CodeBlock};
use crate::asm::x86_64::*;
use crate::backend::ir::*;

// Use the x86 register type for this platform
pub type Reg = X86Reg;

// Callee-saved registers
pub const CFP: Opnd = Opnd::Reg(R13_REG);
pub const EC: Opnd = Opnd::Reg(R12_REG);
pub const SP: Opnd = Opnd::Reg(RBX_REG);

/// Map Opnd to X86Opnd
impl From<Opnd> for X86Opnd {
    fn from(opnd: Opnd) -> Self {
        match opnd {
            // NOTE: these operand types need to be lowered first
            //Value(VALUE),       // Immediate Ruby value, may be GC'd, movable
            //InsnOut(usize),     // Output of a preceding instruction in this block

            Opnd::InsnOut(idx) => panic!("InsnOut operand made it past register allocation"),

            Opnd::None => X86Opnd::None,

            Opnd::UImm(val) => uimm_opnd(val),
            Opnd::Imm(val) => imm_opnd(val),

            // General-purpose register
            Opnd::Reg(reg) => X86Opnd::Reg(reg),

            // Memory operand with displacement
            Opnd::Mem(Mem{ num_bits, base_reg, disp }) => {
                mem_opnd(num_bits, X86Opnd::Reg(base_reg), disp)
            }

            _ => panic!("unsupported x86 operand type")
        }
    }
}

impl Assembler
{
    // Get the list of registers from which we can allocate on this platform
    pub fn get_scratch_regs() -> Vec<Reg>
    {
        vec![
            RAX_REG,
            RCX_REG,
        ]
    }

    // Emit platform-specific machine code
    fn target_split(mut self) -> Assembler
    {
        let live_ranges: Vec<usize> = std::mem::take(&mut self.live_ranges);

        self.transform_insns(|asm, index, op, opnds, target| {
            match op {
                Op::Add | Op::Sub | Op::And => {
                    match opnds.as_slice() {
                        // Instruction output whose live range spans beyond this instruction
                        [Opnd::InsnOut(out_idx), _] => {
                            if live_ranges[*out_idx] > index {
                                let opnd0 = asm.load(opnds[0]);
                                asm.push_insn(op, vec![opnd0, opnds[1]], None);
                                return;
                            }
                        },

                        [Opnd::Mem(_), _] => {
                            let opnd0 = asm.load(opnds[0]);
                            asm.push_insn(op, vec![opnd0, opnds[1]], None);
                            return;
                        },

                        _ => {}
                    }
                },
                _ => {}
            };

            asm.push_insn(op, opnds, target);
        })
    }

    // Emit platform-specific machine code
    pub fn target_emit(&self, cb: &mut CodeBlock)
    {
        // For each instruction
        for insn in &self.insns {
            match insn.op {
                // TODO: need to map the position of comments in the machine code
                Op::Comment => {},

                Op::Label => {},

                Op::Add => {
                    assert_eq!(insn.out, insn.opnds[0]);
                    add(cb, insn.opnds[0].into(), insn.opnds[1].into())
                },

                Op::Load => mov(cb, insn.out.into(), insn.opnds[0].into()),
                //Store
                Op::Mov => mov(cb, insn.opnds[0].into(), insn.opnds[1].into()),

                // Test and set flags
                Op::Test => test(cb, insn.opnds[0].into(), insn.opnds[1].into()),

                /*
                Cmp,
                Jnz,
                Jbe,
                */

                _ => panic!("unsupported instruction passed to x86 backend")
            };
        }
    }

    // Optimize and compile the stored instructions
    pub fn compile_with_regs(self, cb: &mut CodeBlock, regs: Vec<Reg>)
    {
        self
        .target_split()
        .split_loads()
        .alloc_regs(regs)
        .target_emit(cb);
    }
}
