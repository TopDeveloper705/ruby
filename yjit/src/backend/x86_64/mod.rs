#![allow(dead_code)]
#![allow(unused_variables)]
#![allow(unused_imports)]

use std::mem::take;

use crate::asm::*;
use crate::asm::x86_64::*;
use crate::codegen::{JITState};
use crate::cruby::*;
use crate::backend::ir::*;
use crate::codegen::CodegenGlobals;

// Use the x86 register type for this platform
pub type Reg = X86Reg;

// Callee-saved registers
pub const _CFP: Opnd = Opnd::Reg(R13_REG);
pub const _EC: Opnd = Opnd::Reg(R12_REG);
pub const _SP: Opnd = Opnd::Reg(RBX_REG);

// C argument registers on this platform
pub const _C_ARG_OPNDS: [Opnd; 6] = [
    Opnd::Reg(RDI_REG),
    Opnd::Reg(RSI_REG),
    Opnd::Reg(RDX_REG),
    Opnd::Reg(RCX_REG),
    Opnd::Reg(R8_REG),
    Opnd::Reg(R9_REG)
];

// C return value register on this platform
pub const C_RET_REG: Reg = RAX_REG;
pub const _C_RET_OPND: Opnd = Opnd::Reg(RAX_REG);

// The number of bytes that are generated by jmp_ptr
pub const JMP_PTR_BYTES: usize = 6;

/// Map Opnd to X86Opnd
impl From<Opnd> for X86Opnd {
    fn from(opnd: Opnd) -> Self {
        match opnd {
            // NOTE: these operand types need to be lowered first
            //Value(VALUE),       // Immediate Ruby value, may be GC'd, movable
            //InsnOut(usize),     // Output of a preceding instruction in this block

            Opnd::InsnOut{..} => panic!("InsnOut operand made it past register allocation"),

            Opnd::UImm(val) => uimm_opnd(val),
            Opnd::Imm(val) => imm_opnd(val),
            Opnd::Value(VALUE(uimm)) => uimm_opnd(uimm as u64),

            // General-purpose register
            Opnd::Reg(reg) => X86Opnd::Reg(reg),

            // Memory operand with displacement
            Opnd::Mem(Mem{ base: MemBase::Reg(reg_no), num_bits, disp }) => {
                let reg = X86Reg {
                    reg_no,
                    num_bits: 64,
                    reg_type: RegType::GP
                };

                mem_opnd(num_bits, X86Opnd::Reg(reg), disp)
            }

            Opnd::None => panic!(
                "Attempted to lower an Opnd::None. This often happens when an out operand was not allocated for an instruction because the output of the instruction was not used. Please ensure you are using the output."
            ),

            _ => panic!("unsupported x86 operand type")
        }
    }
}

/// Also implement going from a reference to an operand for convenience.
impl From<&Opnd> for X86Opnd {
    fn from(opnd: &Opnd) -> Self {
        X86Opnd::from(*opnd)
    }
}

impl Assembler
{
    // A special scratch register for intermediate processing.
    // Note: right now this is only used by LeaLabel because label_ref accepts
    // a closure and we don't want it to have to capture anything.
    const SCRATCH0: X86Opnd = X86Opnd::Reg(R11_REG);

    /// Get the list of registers from which we can allocate on this platform
    pub fn get_alloc_regs() -> Vec<Reg>
    {
        vec![
            RAX_REG,
            RCX_REG,
            RDX_REG,
        ]
    }

    /// Get a list of all of the caller-save registers
    pub fn get_caller_save_regs() -> Vec<Reg> {
        vec![RAX_REG, RCX_REG, RDX_REG, RSI_REG, RDI_REG, R8_REG, R9_REG, R10_REG, R11_REG]
    }

    // These are the callee-saved registers in the x86-64 SysV ABI
    // RBX, RSP, RBP, and R12–R15

    /// Split IR instructions for the x86 platform
    fn x86_split(mut self) -> Assembler
    {
        let live_ranges: Vec<usize> = take(&mut self.live_ranges);
        let mut asm = Assembler::new_with_label_names(take(&mut self.label_names));
        let mut iterator = self.into_draining_iter();

        while let Some((index, mut insn)) = iterator.next_unmapped() {
            // When we're iterating through the instructions with x86_split, we
            // need to know the previous live ranges in order to tell if a
            // register lasts beyond the current instruction. So instead of
            // using next_mapped, we call next_unmapped. When you're using the
            // next_unmapped API, you need to make sure that you map each
            // operand that could reference an old index, which means both
            // Opnd::InsnOut operands and Opnd::Mem operands with a base of
            // MemBase::InsnOut.
            //
            // You need to ensure that you only map it _once_, because otherwise
            // you'll end up mapping an incorrect index which could end up being
            // out of bounds of the old set of indices.
            //
            // We handle all of that mapping here to ensure that it's only
            // mapped once. We also handle loading Opnd::Value operands into
            // registers here so that all mapping happens in one place. We load
            // Opnd::Value operands into registers here because:
            //
            //   - Most instructions can't be encoded with 64-bit immediates.
            //   - We look for Op::Load specifically when emiting to keep GC'ed
            //     VALUEs alive. This is a sort of canonicalization.
            let mut unmapped_opnds: Vec<Opnd> = vec![];

            let is_load = matches!(insn, Insn::Load { .. } | Insn::LoadInto { .. });
            let mut opnd_iter = insn.opnd_iter_mut();

            while let Some(opnd) = opnd_iter.next() {
                unmapped_opnds.push(*opnd);

                *opnd = if is_load {
                    iterator.map_opnd(*opnd)
                } else if let Opnd::Value(value) = opnd {
                    // Since mov(mem64, imm32) sign extends, as_i64() makes sure
                    // we split when the extended value is different.
                    if !value.special_const_p() || imm_num_bits(value.as_i64()) > 32 {
                        asm.load(iterator.map_opnd(*opnd))
                    } else {
                        Opnd::UImm(value.as_u64())
                    }
                } else {
                    iterator.map_opnd(*opnd)
                }
            }

            // We are replacing instructions here so we know they are already
            // being used. It is okay not to use their output here.
            #[allow(unused_must_use)]
            match &mut insn {
                Insn::Add { left, right, out } |
                Insn::Sub { left, right, out } |
                Insn::And { left, right, out } |
                Insn::Or { left, right, out } |
                Insn::Xor { left, right, out } => {
                    match (unmapped_opnds[0], unmapped_opnds[1]) {
                        (Opnd::Mem(_), Opnd::Mem(_)) => {
                            *left = asm.load(*left);
                            *right = asm.load(*right);
                        },
                        (Opnd::Mem(_), Opnd::UImm(_) | Opnd::Imm(_)) => {
                            *left = asm.load(*left);
                        },
                        // Instruction output whose live range spans beyond this instruction
                        (Opnd::InsnOut { idx, .. }, _) => {
                            if live_ranges[idx] > index {
                                *left = asm.load(*left);
                            }
                        },
                        // We have to load memory operands to avoid corrupting them
                        (Opnd::Mem(_) | Opnd::Reg(_), _) => {
                            *left = asm.load(*left);
                        },
                        _ => {}
                    };

                    *out = asm.next_opnd_out(Opnd::match_num_bits(&[*left, *right]));
                    asm.push_insn(insn);
                },
                Insn::Cmp { left, right } |
                Insn::Test { left, right } => {
                    if let (Opnd::Mem(_), Opnd::Mem(_)) = (&left, &right) {
                        let loaded = asm.load(*right);
                        *right = loaded;
                    }

                    asm.push_insn(insn);
                },
                // These instructions modify their input operand in-place, so we
                // may need to load the input value to preserve it
                Insn::LShift { opnd, shift, out } |
                Insn::RShift { opnd, shift, out } |
                Insn::URShift { opnd, shift, out } => {
                    match (&unmapped_opnds[0], &unmapped_opnds[1]) {
                        // Instruction output whose live range spans beyond this instruction
                        (Opnd::InsnOut { idx, .. }, _) => {
                            if live_ranges[*idx] > index {
                                *opnd = asm.load(*opnd);
                            }
                        },
                        // We have to load memory operands to avoid corrupting them
                        (Opnd::Mem(_) | Opnd::Reg(_), _) => {
                            *opnd = asm.load(*opnd);
                        },
                        _ => {}
                    };

                    *out = asm.next_opnd_out(Opnd::match_num_bits(&[*opnd, *shift]));
                    asm.push_insn(insn);
                },
                Insn::CSelZ { truthy, falsy, out } |
                Insn::CSelNZ { truthy, falsy, out } |
                Insn::CSelE { truthy, falsy, out } |
                Insn::CSelNE { truthy, falsy, out } |
                Insn::CSelL { truthy, falsy, out } |
                Insn::CSelLE { truthy, falsy, out } |
                Insn::CSelG { truthy, falsy, out } |
                Insn::CSelGE { truthy, falsy, out } => {
                    match unmapped_opnds[0] {
                        // If we have an instruction output whose live range
                        // spans beyond this instruction, we have to load it.
                        Opnd::InsnOut { idx, .. } => {
                            if live_ranges[idx] > index {
                                *truthy = asm.load(*truthy);
                            }
                        },
                        Opnd::UImm(_) | Opnd::Imm(_) | Opnd::Value(_) => {
                            *truthy = asm.load(*truthy);
                        },
                        _ => {}
                    };

                    match falsy {
                        Opnd::UImm(_) | Opnd::Imm(_) => {
                            *falsy = asm.load(*falsy);
                        },
                        _ => {}
                    };

                    *out = asm.next_opnd_out(Opnd::match_num_bits(&[*truthy, *falsy]));
                    asm.push_insn(insn);
                },
                Insn::Mov { dest, src } => {
                    match (&dest, &src) {
                        (Opnd::Mem(_), Opnd::Mem(_)) => {
                            // We load opnd1 because for mov, opnd0 is the output
                            let opnd1 = asm.load(*src);
                            asm.mov(*dest, opnd1);
                        },
                        (Opnd::Mem(_), Opnd::UImm(value)) => {
                            // 32-bit values will be sign-extended
                            if imm_num_bits(*value as i64) > 32 {
                                let opnd1 = asm.load(*src);
                                asm.mov(*dest, opnd1);
                            } else {
                                asm.mov(*dest, *src);
                            }
                        },
                        (Opnd::Mem(_), Opnd::Imm(value)) => {
                            if imm_num_bits(*value) > 32 {
                                let opnd1 = asm.load(*src);
                                asm.mov(*dest, opnd1);
                            } else {
                                asm.mov(*dest, *src);
                            }
                        },
                        _ => {
                            asm.mov(*dest, *src);
                        }
                    }
                },
                Insn::Not { opnd, .. } => {
                    let opnd0 = match unmapped_opnds[0] {
                        // If we have an instruction output whose live range
                        // spans beyond this instruction, we have to load it.
                        Opnd::InsnOut { idx, .. } => {
                            if live_ranges[idx] > index {
                                asm.load(*opnd)
                            } else {
                                *opnd
                            }
                        },
                        // We have to load memory and register operands to avoid
                        // corrupting them.
                        Opnd::Mem(_) | Opnd::Reg(_) => {
                            asm.load(*opnd)
                        },
                        // Otherwise we can just reuse the existing operand.
                        _ => *opnd
                    };

                    asm.not(opnd0);
                },
                Insn::CCall { opnds, fptr, .. } => {
                    assert!(opnds.len() <= C_ARG_OPNDS.len());

                    // Load each operand into the corresponding argument
                    // register.
                    for (idx, opnd) in opnds.into_iter().enumerate() {
                        asm.load_into(C_ARG_OPNDS[idx], *opnd);
                    }

                    // Now we push the CCall without any arguments so that it
                    // just performs the call.
                    asm.ccall(*fptr, vec![]);
                },
                _ => {
                    if insn.out_opnd().is_some() {
                        let out_num_bits = Opnd::match_num_bits_iter(insn.opnd_iter());
                        let out = insn.out_opnd_mut().unwrap();
                        *out = asm.next_opnd_out(out_num_bits);
                    }

                    asm.push_insn(insn);
                }
            };

            iterator.map_insn_index(&mut asm);
        }

        asm
    }

    /// Emit platform-specific machine code
    pub fn x86_emit(&mut self, cb: &mut CodeBlock) -> Vec<u32>
    {
        /// For some instructions, we want to be able to lower a 64-bit operand
        /// without requiring more registers to be available in the register
        /// allocator. So we just use the SCRATCH0 register temporarily to hold
        /// the value before we immediately use it.
        fn emit_64bit_immediate(cb: &mut CodeBlock, opnd: &Opnd) -> X86Opnd {
            match opnd {
                Opnd::Imm(value) => {
                    // 32-bit values will be sign-extended
                    if imm_num_bits(*value) > 32 {
                        mov(cb, Assembler::SCRATCH0, opnd.into());
                        Assembler::SCRATCH0
                    } else {
                        opnd.into()
                    }
                },
                Opnd::UImm(value) => {
                    // 32-bit values will be sign-extended
                    if imm_num_bits(*value as i64) > 32 {
                        mov(cb, Assembler::SCRATCH0, opnd.into());
                        Assembler::SCRATCH0
                    } else {
                        opnd.into()
                    }
                },
                _ => opnd.into()
            }
        }


        fn emit_csel(cb: &mut CodeBlock, truthy: Opnd, falsy: Opnd, out: Opnd, cmov_fn: fn(&mut CodeBlock, X86Opnd, X86Opnd)) {
            if out != truthy {
                mov(cb, out.into(), truthy.into());
            }
            cmov_fn(cb, out.into(), falsy.into());
        }

        //dbg!(&self.insns);

        // List of GC offsets
        let mut gc_offsets: Vec<u32> = Vec::new();

        // For each instruction
        let start_write_pos = cb.get_write_pos();
        let mut insns_idx: usize = 0;
        while let Some(insn) = self.insns.get(insns_idx) {
            let src_ptr = cb.get_write_ptr();
            let had_dropped_bytes = cb.has_dropped_bytes();
            let old_label_state = cb.get_label_state();
            let mut insn_gc_offsets: Vec<u32> = Vec::new();

            match insn {
                Insn::Comment(text) => {
                    if cfg!(feature = "disasm") {
                        cb.add_comment(text);
                    }
                },

                // Write the label at the current position
                Insn::Label(target) => {
                    cb.write_label(target.unwrap_label_idx());
                },

                // Report back the current position in the generated code
                Insn::PosMarker(pos_marker) => {
                    pos_marker(cb.get_write_ptr());
                },

                Insn::BakeString(text) => {
                    for byte in text.as_bytes() {
                        cb.write_byte(*byte);
                    }

                    // Add a null-terminator byte for safety (in case we pass
                    // this to C code)
                    cb.write_byte(0);
                },

                Insn::Add { left, right, .. } => {
                    let opnd1 = emit_64bit_immediate(cb, right);
                    add(cb, left.into(), opnd1);
                },

                Insn::FrameSetup => {},
                Insn::FrameTeardown => {},

                Insn::Sub { left, right, .. } => {
                    let opnd1 = emit_64bit_immediate(cb, right);
                    sub(cb, left.into(), opnd1);
                },

                Insn::And { left, right, .. } => {
                    let opnd1 = emit_64bit_immediate(cb, right);
                    and(cb, left.into(), opnd1);
                },

                Insn::Or { left, right, .. } => {
                    let opnd1 = emit_64bit_immediate(cb, right);
                    or(cb, left.into(), opnd1);
                },

                Insn::Xor { left, right, .. } => {
                    let opnd1 = emit_64bit_immediate(cb, right);
                    xor(cb, left.into(), opnd1);
                },

                Insn::Not { opnd, .. } => {
                    not(cb, opnd.into());
                },

                Insn::LShift { opnd, shift , ..} => {
                    shl(cb, opnd.into(), shift.into())
                },

                Insn::RShift { opnd, shift , ..} => {
                    sar(cb, opnd.into(), shift.into())
                },

                Insn::URShift { opnd, shift, .. } => {
                    shr(cb, opnd.into(), shift.into())
                },

                Insn::Store { dest, src } => {
                    mov(cb, dest.into(), src.into());
                },

                // This assumes only load instructions can contain references to GC'd Value operands
                Insn::Load { opnd, out } |
                Insn::LoadInto { dest: out, opnd } => {
                    match opnd {
                        Opnd::Value(val) if val.heap_object_p() => {
                            // Using movabs because mov might write value in 32 bits
                            movabs(cb, out.into(), val.0 as _);
                            // The pointer immediate is encoded as the last part of the mov written out
                            let ptr_offset: u32 = (cb.get_write_pos() as u32) - (SIZEOF_VALUE as u32);
                            insn_gc_offsets.push(ptr_offset);
                        }
                        _ => mov(cb, out.into(), opnd.into())
                    }
                },

                Insn::LoadSExt { opnd, out } => {
                    movsx(cb, out.into(), opnd.into());
                },

                Insn::Mov { dest, src } => {
                    mov(cb, dest.into(), src.into());
                },

                // Load effective address
                Insn::Lea { opnd, out } => {
                    lea(cb, out.into(), opnd.into());
                },

                // Load relative address
                Insn::LeaLabel { target, out } => {
                    let label_idx = target.unwrap_label_idx();

                    cb.label_ref(label_idx, 7, |cb, src_addr, dst_addr| {
                        let disp = dst_addr - src_addr;
                        lea(cb, Self::SCRATCH0, mem_opnd(8, RIP, disp.try_into().unwrap()));
                    });

                    mov(cb, out.into(), Self::SCRATCH0);
                },

                // Push and pop to/from the C stack
                Insn::CPush(opnd) => {
                    push(cb, opnd.into());
                },
                Insn::CPop { out } => {
                    pop(cb, out.into());
                },
                Insn::CPopInto(opnd) => {
                    pop(cb, opnd.into());
                },

                // Push and pop to the C stack all caller-save registers and the
                // flags
                Insn::CPushAll => {
                    let regs = Assembler::get_caller_save_regs();

                    for reg in regs {
                        push(cb, X86Opnd::Reg(reg));
                    }
                    pushfq(cb);
                },
                Insn::CPopAll => {
                    let regs = Assembler::get_caller_save_regs();

                    popfq(cb);
                    for reg in regs.into_iter().rev() {
                        pop(cb, X86Opnd::Reg(reg));
                    }
                },

                // C function call
                Insn::CCall { fptr, .. } => {
                    call_ptr(cb, RAX, *fptr);
                },

                Insn::CRet(opnd) => {
                    // TODO: bias allocation towards return register
                    if *opnd != Opnd::Reg(C_RET_REG) {
                        mov(cb, RAX, opnd.into());
                    }

                    ret(cb);
                },

                // Compare
                Insn::Cmp { left, right } => {
                    let num_bits = match right {
                        Opnd::Imm(value) => Some(imm_num_bits(*value)),
                        Opnd::UImm(value) => Some(uimm_num_bits(*value)),
                        _ => None
                    };

                    // If the immediate is less than 64 bits (like 32, 16, 8), and the operand
                    // sizes match, then we can represent it as an immediate in the instruction
                    // without moving it to a register first.
                    // IOW, 64 bit immediates must always be moved to a register
                    // before comparisons, where other sizes may be encoded
                    // directly in the instruction.
                    if num_bits.is_some() && left.num_bits() == num_bits && num_bits.unwrap() < 64 {
                        cmp(cb, left.into(), right.into());
                    } else {
                        let emitted = emit_64bit_immediate(cb, right);
                        cmp(cb, left.into(), emitted);
                    }
                }

                // Test and set flags
                Insn::Test { left, right } => {
                    let emitted = emit_64bit_immediate(cb, right);
                    test(cb, left.into(), emitted);
                }

                Insn::JmpOpnd(opnd) => {
                    jmp_rm(cb, opnd.into());
                }

                // Conditional jump to a label
                Insn::Jmp(target) => {
                    match *target {
                        Target::CodePtr(code_ptr) | Target::SideExitPtr(code_ptr) => jmp_ptr(cb, code_ptr),
                        Target::Label(label_idx) => jmp_label(cb, label_idx),
                    }
                }

                Insn::Je(target) => {
                    match *target {
                        Target::CodePtr(code_ptr) | Target::SideExitPtr(code_ptr) => je_ptr(cb, code_ptr),
                        Target::Label(label_idx) => je_label(cb, label_idx),
                    }
                }

                Insn::Jne(target) => {
                    match *target {
                        Target::CodePtr(code_ptr) | Target::SideExitPtr(code_ptr) => jne_ptr(cb, code_ptr),
                        Target::Label(label_idx) => jne_label(cb, label_idx),
                    }
                }

                Insn::Jl(target) => {
                    match *target {
                        Target::CodePtr(code_ptr) | Target::SideExitPtr(code_ptr) => jl_ptr(cb, code_ptr),
                        Target::Label(label_idx) => jl_label(cb, label_idx),
                    }
                },

                Insn::Jbe(target) => {
                    match *target {
                        Target::CodePtr(code_ptr) | Target::SideExitPtr(code_ptr) => jbe_ptr(cb, code_ptr),
                        Target::Label(label_idx) => jbe_label(cb, label_idx),
                    }
                },

                Insn::Jz(target) => {
                    match *target {
                        Target::CodePtr(code_ptr) | Target::SideExitPtr(code_ptr) => jz_ptr(cb, code_ptr),
                        Target::Label(label_idx) => jz_label(cb, label_idx),
                    }
                }

                Insn::Jnz(target) => {
                    match *target {
                        Target::CodePtr(code_ptr) | Target::SideExitPtr(code_ptr) => jnz_ptr(cb, code_ptr),
                        Target::Label(label_idx) => jnz_label(cb, label_idx),
                    }
                }

                Insn::Jo(target) => {
                    match *target {
                        Target::CodePtr(code_ptr) | Target::SideExitPtr(code_ptr) => jo_ptr(cb, code_ptr),
                        Target::Label(label_idx) => jo_label(cb, label_idx),
                    }
                }

                // Atomically increment a counter at a given memory location
                Insn::IncrCounter { mem, value } => {
                    assert!(matches!(mem, Opnd::Mem(_)));
                    assert!(matches!(value, Opnd::UImm(_) | Opnd::Imm(_) ) );
                    write_lock_prefix(cb);
                    add(cb, mem.into(), value.into());
                },

                Insn::Breakpoint => int3(cb),

                Insn::CSelZ { truthy, falsy, out } => {
                    emit_csel(cb, *truthy, *falsy, *out, cmovnz);
                },
                Insn::CSelNZ { truthy, falsy, out } => {
                    emit_csel(cb, *truthy, *falsy, *out, cmovz);
                },
                Insn::CSelE { truthy, falsy, out } => {
                    emit_csel(cb, *truthy, *falsy, *out, cmovne);
                },
                Insn::CSelNE { truthy, falsy, out } => {
                    emit_csel(cb, *truthy, *falsy, *out, cmove);
                },
                Insn::CSelL { truthy, falsy, out } => {
                    emit_csel(cb, *truthy, *falsy, *out, cmovge);
                },
                Insn::CSelLE { truthy, falsy, out } => {
                    emit_csel(cb, *truthy, *falsy, *out, cmovg);
                },
                Insn::CSelG { truthy, falsy, out } => {
                    emit_csel(cb, *truthy, *falsy, *out, cmovle);
                },
                Insn::CSelGE { truthy, falsy, out } => {
                    emit_csel(cb, *truthy, *falsy, *out, cmovl);
                }
                Insn::LiveReg { .. } => (), // just a reg alloc signal, no code
                Insn::PadInvalPatch => {
                    let code_size = cb.get_write_pos().saturating_sub(std::cmp::max(start_write_pos, cb.page_start_pos()));
                    if code_size < JMP_PTR_BYTES {
                        nop(cb, (JMP_PTR_BYTES - code_size) as u32);
                    }
                }

                // We want to keep the panic here because some instructions that
                // we feed to the backend could get lowered into other
                // instructions. So it's possible that some of our backend
                // instructions can never make it to the emit stage.
                #[allow(unreachable_patterns)]
                _ => panic!("unsupported instruction passed to x86 backend: {:?}", insn)
            };

            // On failure, jump to the next page and retry the current insn
            if !had_dropped_bytes && cb.has_dropped_bytes() && cb.next_page(src_ptr, jmp_ptr) {
                // Reset cb states before retrying the current Insn
                cb.set_label_state(old_label_state);
            } else {
                insns_idx += 1;
                gc_offsets.append(&mut insn_gc_offsets);
            }
        }

        gc_offsets
    }

    /// Optimize and compile the stored instructions
    pub fn compile_with_regs(self, cb: &mut CodeBlock, regs: Vec<Reg>) -> Vec<u32>
    {
        let mut asm = self.x86_split().alloc_regs(regs);

        // Create label instances in the code block
        for (idx, name) in asm.label_names.iter().enumerate() {
            let label_idx = cb.new_label(name.to_string());
            assert!(label_idx == idx);
        }

        let gc_offsets = asm.x86_emit(cb);

        if cb.has_dropped_bytes() {
            cb.clear_labels();
        } else {
            cb.link_labels();
        }

        gc_offsets
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn setup_asm() -> (Assembler, CodeBlock) {
        (Assembler::new(), CodeBlock::new_dummy(1024))
    }

    #[test]
    fn test_emit_add_lt_32_bits() {
        let (mut asm, mut cb) = setup_asm();

        let _ = asm.add(Opnd::Reg(RAX_REG), Opnd::UImm(0xFF));
        asm.compile_with_num_regs(&mut cb, 1);

        assert_eq!(format!("{:x}", cb), "4889c04881c0ff000000");
    }

    #[test]
    fn test_emit_add_gt_32_bits() {
        let (mut asm, mut cb) = setup_asm();

        let _ = asm.add(Opnd::Reg(RAX_REG), Opnd::UImm(0xFFFF_FFFF_FFFF));
        asm.compile_with_num_regs(&mut cb, 1);

        assert_eq!(format!("{:x}", cb), "4889c049bbffffffffffff00004c01d8");
    }

    #[test]
    fn test_emit_and_lt_32_bits() {
        let (mut asm, mut cb) = setup_asm();

        let _ = asm.and(Opnd::Reg(RAX_REG), Opnd::UImm(0xFF));
        asm.compile_with_num_regs(&mut cb, 1);

        assert_eq!(format!("{:x}", cb), "4889c04881e0ff000000");
    }

    #[test]
    fn test_emit_and_gt_32_bits() {
        let (mut asm, mut cb) = setup_asm();

        let _ = asm.and(Opnd::Reg(RAX_REG), Opnd::UImm(0xFFFF_FFFF_FFFF));
        asm.compile_with_num_regs(&mut cb, 1);

        assert_eq!(format!("{:x}", cb), "4889c049bbffffffffffff00004c21d8");
    }

    #[test]
    fn test_emit_cmp_lt_32_bits() {
        let (mut asm, mut cb) = setup_asm();

        asm.cmp(Opnd::Reg(RAX_REG), Opnd::UImm(0xFF));
        asm.compile_with_num_regs(&mut cb, 0);

        assert_eq!(format!("{:x}", cb), "4881f8ff000000");
    }

    #[test]
    fn test_emit_cmp_gt_32_bits() {
        let (mut asm, mut cb) = setup_asm();

        asm.cmp(Opnd::Reg(RAX_REG), Opnd::UImm(0xFFFF_FFFF_FFFF));
        asm.compile_with_num_regs(&mut cb, 0);

        assert_eq!(format!("{:x}", cb), "49bbffffffffffff00004c39d8");
    }

    #[test]
    fn test_emit_cmp_mem_16_bits_with_imm_16() {
        let (mut asm, mut cb) = setup_asm();

        let shape_opnd = Opnd::mem(16, Opnd::Reg(RAX_REG), 6);

        asm.cmp(shape_opnd, Opnd::UImm(0xF000));
        asm.compile_with_num_regs(&mut cb, 0);

        assert_eq!(format!("{:x}", cb), "6681780600f0");
    }

    #[test]
    fn test_emit_cmp_mem_32_bits_with_imm_32() {
        let (mut asm, mut cb) = setup_asm();

        let shape_opnd = Opnd::mem(32, Opnd::Reg(RAX_REG), 4);

        asm.cmp(shape_opnd, Opnd::UImm(0xF000_0000));
        asm.compile_with_num_regs(&mut cb, 0);

        assert_eq!(format!("{:x}", cb), "817804000000f0");
    }

    #[test]
    fn test_emit_or_lt_32_bits() {
        let (mut asm, mut cb) = setup_asm();

        let _ = asm.or(Opnd::Reg(RAX_REG), Opnd::UImm(0xFF));
        asm.compile_with_num_regs(&mut cb, 1);

        assert_eq!(format!("{:x}", cb), "4889c04881c8ff000000");
    }

    #[test]
    fn test_emit_or_gt_32_bits() {
        let (mut asm, mut cb) = setup_asm();

        let _ = asm.or(Opnd::Reg(RAX_REG), Opnd::UImm(0xFFFF_FFFF_FFFF));
        asm.compile_with_num_regs(&mut cb, 1);

        assert_eq!(format!("{:x}", cb), "4889c049bbffffffffffff00004c09d8");
    }

    #[test]
    fn test_emit_sub_lt_32_bits() {
        let (mut asm, mut cb) = setup_asm();

        let _ = asm.sub(Opnd::Reg(RAX_REG), Opnd::UImm(0xFF));
        asm.compile_with_num_regs(&mut cb, 1);

        assert_eq!(format!("{:x}", cb), "4889c04881e8ff000000");
    }

    #[test]
    fn test_emit_sub_gt_32_bits() {
        let (mut asm, mut cb) = setup_asm();

        let _ = asm.sub(Opnd::Reg(RAX_REG), Opnd::UImm(0xFFFF_FFFF_FFFF));
        asm.compile_with_num_regs(&mut cb, 1);

        assert_eq!(format!("{:x}", cb), "4889c049bbffffffffffff00004c29d8");
    }

    #[test]
    fn test_emit_test_lt_32_bits() {
        let (mut asm, mut cb) = setup_asm();

        asm.test(Opnd::Reg(RAX_REG), Opnd::UImm(0xFF));
        asm.compile_with_num_regs(&mut cb, 0);

        assert_eq!(format!("{:x}", cb), "f6c0ff");
    }

    #[test]
    fn test_emit_test_gt_32_bits() {
        let (mut asm, mut cb) = setup_asm();

        asm.test(Opnd::Reg(RAX_REG), Opnd::UImm(0xFFFF_FFFF_FFFF));
        asm.compile_with_num_regs(&mut cb, 0);

        assert_eq!(format!("{:x}", cb), "49bbffffffffffff00004c85d8");
    }

    #[test]
    fn test_emit_xor_lt_32_bits() {
        let (mut asm, mut cb) = setup_asm();

        let _ = asm.xor(Opnd::Reg(RAX_REG), Opnd::UImm(0xFF));
        asm.compile_with_num_regs(&mut cb, 1);

        assert_eq!(format!("{:x}", cb), "4889c04881f0ff000000");
    }

    #[test]
    fn test_emit_xor_gt_32_bits() {
        let (mut asm, mut cb) = setup_asm();

        let _ = asm.xor(Opnd::Reg(RAX_REG), Opnd::UImm(0xFFFF_FFFF_FFFF));
        asm.compile_with_num_regs(&mut cb, 1);

        assert_eq!(format!("{:x}", cb), "4889c049bbffffffffffff00004c31d8");
    }
}
