use crate::asm::{imm_num_bits, uimm_num_bits};

/// This operand represents a register.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct A64Reg
{
    // Size in bits
    pub num_bits: u8,

    // Register index number
    pub reg_no: u8,
}

#[derive(Clone, Copy, Debug)]
pub struct A64Mem
{
    // Size in bits
    pub num_bits: u8,

    /// Base register number
    pub base_reg_no: u8,

    /// Constant displacement from the base, not scaled
    pub disp: i32,
}

impl A64Mem {
    pub fn new(reg: A64Opnd, disp: i32) -> Self {
        match reg {
            A64Opnd::Reg(reg) => {
                Self {
                    num_bits: reg.num_bits,
                    base_reg_no: reg.reg_no,
                    disp
                }
            },
            _ => panic!("Expected register operand")
        }
    }
}

#[derive(Clone, Copy, Debug)]
pub enum A64Opnd
{
    // Dummy operand
    None,

    // Immediate value
    Imm(i64),

    // Unsigned immediate
    UImm(u64),

    // Register
    Reg(A64Reg),

    // Memory
    Mem(A64Mem)
}

impl A64Opnd {
    /// Create a new immediate value operand.
    pub fn new_imm(value: i64) -> Self {
        A64Opnd::Imm(value)
    }

    /// Create a new unsigned immediate value operand.
    pub fn new_uimm(value: u64) -> Self {
        A64Opnd::UImm(value)
    }

    /// Creates a new memory operand.
    pub fn new_mem(reg: A64Opnd, disp: i32) -> Self {
        A64Opnd::Mem(A64Mem::new(reg, disp))
    }

    /// Convenience function to check if this operand is a register.
    pub fn is_reg(&self) -> bool {
        match self {
            A64Opnd::Reg(_) => true,
            _ => false
        }
    }
}

pub const X0_REG: A64Reg = A64Reg { num_bits: 64, reg_no: 0 };
pub const X1_REG: A64Reg = A64Reg { num_bits: 64, reg_no: 1 };
pub const X2_REG: A64Reg = A64Reg { num_bits: 64, reg_no: 2 };
pub const X3_REG: A64Reg = A64Reg { num_bits: 64, reg_no: 3 };

pub const X12_REG: A64Reg = A64Reg { num_bits: 64, reg_no: 12 };
pub const X13_REG: A64Reg = A64Reg { num_bits: 64, reg_no: 13 };

// 64-bit registers
pub const X0: A64Opnd = A64Opnd::Reg(X0_REG);
pub const X1: A64Opnd = A64Opnd::Reg(X1_REG);
pub const X2: A64Opnd = A64Opnd::Reg(X2_REG);
pub const X3: A64Opnd = A64Opnd::Reg(X3_REG);
pub const X4: A64Opnd = A64Opnd::Reg(A64Reg { num_bits: 64, reg_no: 4 });
pub const X5: A64Opnd = A64Opnd::Reg(A64Reg { num_bits: 64, reg_no: 5 });
pub const X6: A64Opnd = A64Opnd::Reg(A64Reg { num_bits: 64, reg_no: 6 });
pub const X7: A64Opnd = A64Opnd::Reg(A64Reg { num_bits: 64, reg_no: 7 });
pub const X8: A64Opnd = A64Opnd::Reg(A64Reg { num_bits: 64, reg_no: 8 });
pub const X9: A64Opnd = A64Opnd::Reg(A64Reg { num_bits: 64, reg_no: 9 });
pub const X10: A64Opnd = A64Opnd::Reg(A64Reg { num_bits: 64, reg_no: 10 });
pub const X11: A64Opnd = A64Opnd::Reg(A64Reg { num_bits: 64, reg_no: 11 });
pub const X12: A64Opnd = A64Opnd::Reg(X12_REG);
pub const X13: A64Opnd = A64Opnd::Reg(X13_REG);
pub const X14: A64Opnd = A64Opnd::Reg(A64Reg { num_bits: 64, reg_no: 14 });
pub const X15: A64Opnd = A64Opnd::Reg(A64Reg { num_bits: 64, reg_no: 15 });
pub const X16: A64Opnd = A64Opnd::Reg(A64Reg { num_bits: 64, reg_no: 16 });
pub const X17: A64Opnd = A64Opnd::Reg(A64Reg { num_bits: 64, reg_no: 17 });
pub const X18: A64Opnd = A64Opnd::Reg(A64Reg { num_bits: 64, reg_no: 18 });
pub const X19: A64Opnd = A64Opnd::Reg(A64Reg { num_bits: 64, reg_no: 19 });
pub const X20: A64Opnd = A64Opnd::Reg(A64Reg { num_bits: 64, reg_no: 20 });
pub const X21: A64Opnd = A64Opnd::Reg(A64Reg { num_bits: 64, reg_no: 21 });
pub const X22: A64Opnd = A64Opnd::Reg(A64Reg { num_bits: 64, reg_no: 22 });
pub const X23: A64Opnd = A64Opnd::Reg(A64Reg { num_bits: 64, reg_no: 23 });
pub const X24: A64Opnd = A64Opnd::Reg(A64Reg { num_bits: 64, reg_no: 24 });
pub const X25: A64Opnd = A64Opnd::Reg(A64Reg { num_bits: 64, reg_no: 25 });
pub const X26: A64Opnd = A64Opnd::Reg(A64Reg { num_bits: 64, reg_no: 26 });
pub const X27: A64Opnd = A64Opnd::Reg(A64Reg { num_bits: 64, reg_no: 27 });
pub const X28: A64Opnd = A64Opnd::Reg(A64Reg { num_bits: 64, reg_no: 28 });
pub const X29: A64Opnd = A64Opnd::Reg(A64Reg { num_bits: 64, reg_no: 29 });
pub const X30: A64Opnd = A64Opnd::Reg(A64Reg { num_bits: 64, reg_no: 30 });

// 32-bit registers
pub const W0: A64Reg = A64Reg { num_bits: 32, reg_no: 0 };
pub const W1: A64Reg = A64Reg { num_bits: 32, reg_no: 1 };
pub const W2: A64Reg = A64Reg { num_bits: 32, reg_no: 2 };
pub const W3: A64Reg = A64Reg { num_bits: 32, reg_no: 3 };
pub const W4: A64Reg = A64Reg { num_bits: 32, reg_no: 4 };
pub const W5: A64Reg = A64Reg { num_bits: 32, reg_no: 5 };
pub const W6: A64Reg = A64Reg { num_bits: 32, reg_no: 6 };
pub const W7: A64Reg = A64Reg { num_bits: 32, reg_no: 7 };
pub const W8: A64Reg = A64Reg { num_bits: 32, reg_no: 8 };
pub const W9: A64Reg = A64Reg { num_bits: 32, reg_no: 9 };
pub const W10: A64Reg = A64Reg { num_bits: 32, reg_no: 10 };
pub const W11: A64Reg = A64Reg { num_bits: 32, reg_no: 11 };
pub const W12: A64Reg = A64Reg { num_bits: 32, reg_no: 12 };
pub const W13: A64Reg = A64Reg { num_bits: 32, reg_no: 13 };
pub const W14: A64Reg = A64Reg { num_bits: 32, reg_no: 14 };
pub const W15: A64Reg = A64Reg { num_bits: 32, reg_no: 15 };
pub const W16: A64Reg = A64Reg { num_bits: 32, reg_no: 16 };
pub const W17: A64Reg = A64Reg { num_bits: 32, reg_no: 17 };
pub const W18: A64Reg = A64Reg { num_bits: 32, reg_no: 18 };
pub const W19: A64Reg = A64Reg { num_bits: 32, reg_no: 19 };
pub const W20: A64Reg = A64Reg { num_bits: 32, reg_no: 20 };
pub const W21: A64Reg = A64Reg { num_bits: 32, reg_no: 21 };
pub const W22: A64Reg = A64Reg { num_bits: 32, reg_no: 22 };
pub const W23: A64Reg = A64Reg { num_bits: 32, reg_no: 23 };
pub const W24: A64Reg = A64Reg { num_bits: 32, reg_no: 24 };
pub const W25: A64Reg = A64Reg { num_bits: 32, reg_no: 25 };
pub const W26: A64Reg = A64Reg { num_bits: 32, reg_no: 26 };
pub const W27: A64Reg = A64Reg { num_bits: 32, reg_no: 27 };
pub const W28: A64Reg = A64Reg { num_bits: 32, reg_no: 28 };
pub const W29: A64Reg = A64Reg { num_bits: 32, reg_no: 29 };
pub const W30: A64Reg = A64Reg { num_bits: 32, reg_no: 30 };

// C argument registers
pub const C_ARG_REGS: [A64Opnd; 4] = [X0, X1, X2, X3];
