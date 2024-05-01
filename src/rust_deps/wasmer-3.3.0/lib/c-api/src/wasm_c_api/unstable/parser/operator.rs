use wasmer_api::wasmparser::Operator;

#[repr(C)]
#[allow(non_camel_case_types)]
pub enum wasmer_parser_operator_t {
    Unreachable,
    Nop,
    Block,
    Loop,
    If,
    Else,
    Try,
    Catch,
    CatchAll,
    Delegate,
    Throw,
    Rethrow,
    Unwind,
    End,
    Br,
    BrIf,
    BrTable,
    Return,
    Call,
    CallIndirect,
    ReturnCall,
    ReturnCallIndirect,
    Drop,
    Select,
    TypedSelect,
    LocalGet,
    LocalSet,
    LocalTee,
    GlobalGet,
    GlobalSet,
    I32Load,
    I64Load,
    F32Load,
    F64Load,
    I32Load8S,
    I32Load8U,
    I32Load16S,
    I32Load16U,
    I64Load8S,
    I64Load8U,
    I64Load16S,
    I64Load16U,
    I64Load32S,
    I64Load32U,
    I32Store,
    I64Store,
    F32Store,
    F64Store,
    I32Store8,
    I32Store16,
    I64Store8,
    I64Store16,
    I64Store32,
    MemorySize,
    MemoryGrow,
    I32Const,
    I64Const,
    F32Const,
    F64Const,
    RefNull,
    RefIsNull,
    RefFunc,
    I32Eqz,
    I32Eq,
    I32Ne,
    I32LtS,
    I32LtU,
    I32GtS,
    I32GtU,
    I32LeS,
    I32LeU,
    I32GeS,
    I32GeU,
    I64Eqz,
    I64Eq,
    I64Ne,
    I64LtS,
    I64LtU,
    I64GtS,
    I64GtU,
    I64LeS,
    I64LeU,
    I64GeS,
    I64GeU,
    F32Eq,
    F32Ne,
    F32Lt,
    F32Gt,
    F32Le,
    F32Ge,
    F64Eq,
    F64Ne,
    F64Lt,
    F64Gt,
    F64Le,
    F64Ge,
    I32Clz,
    I32Ctz,
    I32Popcnt,
    I32Add,
    I32Sub,
    I32Mul,
    I32DivS,
    I32DivU,
    I32RemS,
    I32RemU,
    I32And,
    I32Or,
    I32Xor,
    I32Shl,
    I32ShrS,
    I32ShrU,
    I32Rotl,
    I32Rotr,
    I64Clz,
    I64Ctz,
    I64Popcnt,
    I64Add,
    I64Sub,
    I64Mul,
    I64DivS,
    I64DivU,
    I64RemS,
    I64RemU,
    I64And,
    I64Or,
    I64Xor,
    I64Shl,
    I64ShrS,
    I64ShrU,
    I64Rotl,
    I64Rotr,
    F32Abs,
    F32Neg,
    F32Ceil,
    F32Floor,
    F32Trunc,
    F32Nearest,
    F32Sqrt,
    F32Add,
    F32Sub,
    F32Mul,
    F32Div,
    F32Min,
    F32Max,
    F32Copysign,
    F64Abs,
    F64Neg,
    F64Ceil,
    F64Floor,
    F64Trunc,
    F64Nearest,
    F64Sqrt,
    F64Add,
    F64Sub,
    F64Mul,
    F64Div,
    F64Min,
    F64Max,
    F64Copysign,
    I32WrapI64,
    I32TruncF32S,
    I32TruncF32U,
    I32TruncF64S,
    I32TruncF64U,
    I64ExtendI32S,
    I64ExtendI32U,
    I64TruncF32S,
    I64TruncF32U,
    I64TruncF64S,
    I64TruncF64U,
    F32ConvertI32S,
    F32ConvertI32U,
    F32ConvertI64S,
    F32ConvertI64U,
    F32DemoteF64,
    F64ConvertI32S,
    F64ConvertI32U,
    F64ConvertI64S,
    F64ConvertI64U,
    F64PromoteF32,
    I32ReinterpretF32,
    I64ReinterpretF64,
    F32ReinterpretI32,
    F64ReinterpretI64,
    I32Extend8S,
    I32Extend16S,
    I64Extend8S,
    I64Extend16S,
    I64Extend32S,
    I32TruncSatF32S,
    I32TruncSatF32U,
    I32TruncSatF64S,
    I32TruncSatF64U,
    I64TruncSatF32S,
    I64TruncSatF32U,
    I64TruncSatF64S,
    I64TruncSatF64U,
    MemoryInit,
    DataDrop,
    MemoryCopy,
    MemoryFill,
    TableInit,
    ElemDrop,
    TableCopy,
    TableFill,
    TableGet,
    TableSet,
    TableGrow,
    TableSize,
    MemoryAtomicNotify,
    MemoryAtomicWait32,
    MemoryAtomicWait64,
    AtomicFence,
    I32AtomicLoad,
    I64AtomicLoad,
    I32AtomicLoad8U,
    I32AtomicLoad16U,
    I64AtomicLoad8U,
    I64AtomicLoad16U,
    I64AtomicLoad32U,
    I32AtomicStore,
    I64AtomicStore,
    I32AtomicStore8,
    I32AtomicStore16,
    I64AtomicStore8,
    I64AtomicStore16,
    I64AtomicStore32,
    I32AtomicRmwAdd,
    I64AtomicRmwAdd,
    I32AtomicRmw8AddU,
    I32AtomicRmw16AddU,
    I64AtomicRmw8AddU,
    I64AtomicRmw16AddU,
    I64AtomicRmw32AddU,
    I32AtomicRmwSub,
    I64AtomicRmwSub,
    I32AtomicRmw8SubU,
    I32AtomicRmw16SubU,
    I64AtomicRmw8SubU,
    I64AtomicRmw16SubU,
    I64AtomicRmw32SubU,
    I32AtomicRmwAnd,
    I64AtomicRmwAnd,
    I32AtomicRmw8AndU,
    I32AtomicRmw16AndU,
    I64AtomicRmw8AndU,
    I64AtomicRmw16AndU,
    I64AtomicRmw32AndU,
    I32AtomicRmwOr,
    I64AtomicRmwOr,
    I32AtomicRmw8OrU,
    I32AtomicRmw16OrU,
    I64AtomicRmw8OrU,
    I64AtomicRmw16OrU,
    I64AtomicRmw32OrU,
    I32AtomicRmwXor,
    I64AtomicRmwXor,
    I32AtomicRmw8XorU,
    I32AtomicRmw16XorU,
    I64AtomicRmw8XorU,
    I64AtomicRmw16XorU,
    I64AtomicRmw32XorU,
    I32AtomicRmwXchg,
    I64AtomicRmwXchg,
    I32AtomicRmw8XchgU,
    I32AtomicRmw16XchgU,
    I64AtomicRmw8XchgU,
    I64AtomicRmw16XchgU,
    I64AtomicRmw32XchgU,
    I32AtomicRmwCmpxchg,
    I64AtomicRmwCmpxchg,
    I32AtomicRmw8CmpxchgU,
    I32AtomicRmw16CmpxchgU,
    I64AtomicRmw8CmpxchgU,
    I64AtomicRmw16CmpxchgU,
    I64AtomicRmw32CmpxchgU,
    V128Load,
    V128Store,
    V128Const,
    I8x16Splat,
    I8x16ExtractLaneS,
    I8x16ExtractLaneU,
    I8x16ReplaceLane,
    I16x8Splat,
    I16x8ExtractLaneS,
    I16x8ExtractLaneU,
    I16x8ReplaceLane,
    I32x4Splat,
    I32x4ExtractLane,
    I32x4ReplaceLane,
    I64x2Splat,
    I64x2ExtractLane,
    I64x2ReplaceLane,
    F32x4Splat,
    F32x4ExtractLane,
    F32x4ReplaceLane,
    F64x2Splat,
    F64x2ExtractLane,
    F64x2ReplaceLane,
    I8x16Eq,
    I8x16Ne,
    I8x16LtS,
    I8x16LtU,
    I8x16GtS,
    I8x16GtU,
    I8x16LeS,
    I8x16LeU,
    I8x16GeS,
    I8x16GeU,
    I16x8Eq,
    I16x8Ne,
    I16x8LtS,
    I16x8LtU,
    I16x8GtS,
    I16x8GtU,
    I16x8LeS,
    I16x8LeU,
    I16x8GeS,
    I16x8GeU,
    I32x4Eq,
    I32x4Ne,
    I32x4LtS,
    I32x4LtU,
    I32x4GtS,
    I32x4GtU,
    I32x4LeS,
    I32x4LeU,
    I32x4GeS,
    I32x4GeU,
    I64x2Eq,
    I64x2Ne,
    I64x2LtS,
    I64x2GtS,
    I64x2LeS,
    I64x2GeS,
    F32x4Eq,
    F32x4Ne,
    F32x4Lt,
    F32x4Gt,
    F32x4Le,
    F32x4Ge,
    F64x2Eq,
    F64x2Ne,
    F64x2Lt,
    F64x2Gt,
    F64x2Le,
    F64x2Ge,
    V128Not,
    V128And,
    V128AndNot,
    V128Or,
    V128Xor,
    V128Bitselect,
    V128AnyTrue,
    I8x16Abs,
    I8x16Neg,
    I8x16AllTrue,
    I8x16Bitmask,
    I8x16Shl,
    I8x16ShrS,
    I8x16ShrU,
    I8x16Add,
    I8x16AddSatS,
    I8x16AddSatU,
    I8x16Sub,
    I8x16SubSatS,
    I8x16SubSatU,
    I8x16MinS,
    I8x16MinU,
    I8x16MaxS,
    I8x16MaxU,
    I8x16Popcnt,
    I16x8Abs,
    I16x8Neg,
    I16x8AllTrue,
    I16x8Bitmask,
    I16x8Shl,
    I16x8ShrS,
    I16x8ShrU,
    I16x8Add,
    I16x8AddSatS,
    I16x8AddSatU,
    I16x8Sub,
    I16x8SubSatS,
    I16x8SubSatU,
    I16x8Mul,
    I16x8MinS,
    I16x8MinU,
    I16x8MaxS,
    I16x8MaxU,
    I16x8ExtAddPairwiseI8x16S,
    I16x8ExtAddPairwiseI8x16U,
    I32x4Abs,
    I32x4Neg,
    I32x4AllTrue,
    I32x4Bitmask,
    I32x4Shl,
    I32x4ShrS,
    I32x4ShrU,
    I32x4Add,
    I32x4Sub,
    I32x4Mul,
    I32x4MinS,
    I32x4MinU,
    I32x4MaxS,
    I32x4MaxU,
    I32x4DotI16x8S,
    I32x4ExtAddPairwiseI16x8S,
    I32x4ExtAddPairwiseI16x8U,
    I64x2Abs,
    I64x2Neg,
    I64x2AllTrue,
    I64x2Bitmask,
    I64x2Shl,
    I64x2ShrS,
    I64x2ShrU,
    I64x2Add,
    I64x2Sub,
    I64x2Mul,
    F32x4Ceil,
    F32x4Floor,
    F32x4Trunc,
    F32x4Nearest,
    F64x2Ceil,
    F64x2Floor,
    F64x2Trunc,
    F64x2Nearest,
    F32x4Abs,
    F32x4Neg,
    F32x4Sqrt,
    F32x4Add,
    F32x4Sub,
    F32x4Mul,
    F32x4Div,
    F32x4Min,
    F32x4Max,
    F32x4PMin,
    F32x4PMax,
    F64x2Abs,
    F64x2Neg,
    F64x2Sqrt,
    F64x2Add,
    F64x2Sub,
    F64x2Mul,
    F64x2Div,
    F64x2Min,
    F64x2Max,
    F64x2PMin,
    F64x2PMax,
    I32x4TruncSatF32x4S,
    I32x4TruncSatF32x4U,
    F32x4ConvertI32x4S,
    F32x4ConvertI32x4U,
    I8x16Swizzle,
    I8x16Shuffle,
    V128Load8Splat,
    V128Load16Splat,
    V128Load32Splat,
    V128Load32Zero,
    V128Load64Splat,
    V128Load64Zero,
    I8x16NarrowI16x8S,
    I8x16NarrowI16x8U,
    I16x8NarrowI32x4S,
    I16x8NarrowI32x4U,
    I16x8ExtendLowI8x16S,
    I16x8ExtendHighI8x16S,
    I16x8ExtendLowI8x16U,
    I16x8ExtendHighI8x16U,
    I32x4ExtendLowI16x8S,
    I32x4ExtendHighI16x8S,
    I32x4ExtendLowI16x8U,
    I32x4ExtendHighI16x8U,
    I64x2ExtendLowI32x4S,
    I64x2ExtendHighI32x4S,
    I64x2ExtendLowI32x4U,
    I64x2ExtendHighI32x4U,
    I16x8ExtMulLowI8x16S,
    I16x8ExtMulHighI8x16S,
    I16x8ExtMulLowI8x16U,
    I16x8ExtMulHighI8x16U,
    I32x4ExtMulLowI16x8S,
    I32x4ExtMulHighI16x8S,
    I32x4ExtMulLowI16x8U,
    I32x4ExtMulHighI16x8U,
    I64x2ExtMulLowI32x4S,
    I64x2ExtMulHighI32x4S,
    I64x2ExtMulLowI32x4U,
    I64x2ExtMulHighI32x4U,
    V128Load8x8S,
    V128Load8x8U,
    V128Load16x4S,
    V128Load16x4U,
    V128Load32x2S,
    V128Load32x2U,
    V128Load8Lane,
    V128Load16Lane,
    V128Load32Lane,
    V128Load64Lane,
    V128Store8Lane,
    V128Store16Lane,
    V128Store32Lane,
    V128Store64Lane,
    I8x16RoundingAverageU,
    I16x8RoundingAverageU,
    I16x8Q15MulrSatS,
    F32x4DemoteF64x2Zero,
    F64x2PromoteLowF32x4,
    F64x2ConvertLowI32x4S,
    F64x2ConvertLowI32x4U,
    I32x4TruncSatF64x2SZero,
    I32x4TruncSatF64x2UZero,
    I8x16RelaxedSwizzle,
    I32x4RelaxedTruncSatF32x4S,
    I32x4RelaxedTruncSatF32x4U,
    I32x4RelaxedTruncSatF64x2SZero,
    I32x4RelaxedTruncSatF64x2UZero,
    F32x4Fma,
    F32x4Fms,
    F64x2Fma,
    F64x2Fms,
    I8x16LaneSelect,
    I16x8LaneSelect,
    I32x4LaneSelect,
    I64x2LaneSelect,
    F32x4RelaxedMin,
    F32x4RelaxedMax,
    F64x2RelaxedMin,
    F64x2RelaxedMax,
    I16x8RelaxedQ15mulrS,
    I16x8DotI8x16I7x16S,
    I32x4DotI8x16I7x16AddS,
    F32x4RelaxedDotBf16x8AddF32x4,
}

impl<'a> From<&Operator<'a>> for wasmer_parser_operator_t {
    fn from(operator: &Operator<'a>) -> Self {
        use Operator as O;

        match operator {
            O::Unreachable => Self::Unreachable,
            O::Nop => Self::Nop,
            O::Block { .. } => Self::Block,
            O::Loop { .. } => Self::Loop,
            O::If { .. } => Self::If,
            O::Else => Self::Else,
            O::Try { .. } => Self::Try,
            O::Catch { .. } => Self::Catch,
            O::CatchAll => Self::CatchAll,
            O::Delegate { .. } => Self::Delegate,
            O::Throw { .. } => Self::Throw,
            O::Rethrow { .. } => Self::Rethrow,
            // O::Unwind removed
            O::End => Self::End,
            O::Br { .. } => Self::Br,
            O::BrIf { .. } => Self::BrIf,
            O::BrTable { .. } => Self::BrTable,
            O::Return => Self::Return,
            O::Call { .. } => Self::Call,
            O::CallIndirect { .. } => Self::CallIndirect,
            O::ReturnCall { .. } => Self::ReturnCall,
            O::ReturnCallIndirect { .. } => Self::ReturnCallIndirect,
            O::Drop => Self::Drop,
            O::Select => Self::Select,
            O::TypedSelect { .. } => Self::TypedSelect,
            O::LocalGet { .. } => Self::LocalGet,
            O::LocalSet { .. } => Self::LocalSet,
            O::LocalTee { .. } => Self::LocalTee,
            O::GlobalGet { .. } => Self::GlobalGet,
            O::GlobalSet { .. } => Self::GlobalSet,
            O::I32Load { .. } => Self::I32Load,
            O::I64Load { .. } => Self::I64Load,
            O::F32Load { .. } => Self::F32Load,
            O::F64Load { .. } => Self::F64Load,
            O::I32Load8S { .. } => Self::I32Load8S,
            O::I32Load8U { .. } => Self::I32Load8U,
            O::I32Load16S { .. } => Self::I32Load16S,
            O::I32Load16U { .. } => Self::I32Load16U,
            O::I64Load8S { .. } => Self::I64Load8S,
            O::I64Load8U { .. } => Self::I64Load8U,
            O::I64Load16S { .. } => Self::I64Load16S,
            O::I64Load16U { .. } => Self::I64Load16U,
            O::I64Load32S { .. } => Self::I64Load32S,
            O::I64Load32U { .. } => Self::I64Load32U,
            O::I32Store { .. } => Self::I32Store,
            O::I64Store { .. } => Self::I64Store,
            O::F32Store { .. } => Self::F32Store,
            O::F64Store { .. } => Self::F64Store,
            O::I32Store8 { .. } => Self::I32Store8,
            O::I32Store16 { .. } => Self::I32Store16,
            O::I64Store8 { .. } => Self::I64Store8,
            O::I64Store16 { .. } => Self::I64Store16,
            O::I64Store32 { .. } => Self::I64Store32,
            O::MemorySize { .. } => Self::MemorySize,
            O::MemoryGrow { .. } => Self::MemoryGrow,
            O::I32Const { .. } => Self::I32Const,
            O::I64Const { .. } => Self::I64Const,
            O::F32Const { .. } => Self::F32Const,
            O::F64Const { .. } => Self::F64Const,
            O::RefNull { .. } => Self::RefNull,
            O::RefIsNull => Self::RefIsNull,
            O::RefFunc { .. } => Self::RefFunc,
            O::I32Eqz => Self::I32Eqz,
            O::I32Eq => Self::I32Eq,
            O::I32Ne => Self::I32Ne,
            O::I32LtS => Self::I32LtS,
            O::I32LtU => Self::I32LtU,
            O::I32GtS => Self::I32GtS,
            O::I32GtU => Self::I32GtU,
            O::I32LeS => Self::I32LeS,
            O::I32LeU => Self::I32LeU,
            O::I32GeS => Self::I32GeS,
            O::I32GeU => Self::I32GeU,
            O::I64Eqz => Self::I64Eqz,
            O::I64Eq => Self::I64Eq,
            O::I64Ne => Self::I64Ne,
            O::I64LtS => Self::I64LtS,
            O::I64LtU => Self::I64LtU,
            O::I64GtS => Self::I64GtS,
            O::I64GtU => Self::I64GtU,
            O::I64LeS => Self::I64LeS,
            O::I64LeU => Self::I64LeU,
            O::I64GeS => Self::I64GeS,
            O::I64GeU => Self::I64GeU,
            O::F32Eq => Self::F32Eq,
            O::F32Ne => Self::F32Ne,
            O::F32Lt => Self::F32Lt,
            O::F32Gt => Self::F32Gt,
            O::F32Le => Self::F32Le,
            O::F32Ge => Self::F32Ge,
            O::F64Eq => Self::F64Eq,
            O::F64Ne => Self::F64Ne,
            O::F64Lt => Self::F64Lt,
            O::F64Gt => Self::F64Gt,
            O::F64Le => Self::F64Le,
            O::F64Ge => Self::F64Ge,
            O::I32Clz => Self::I32Clz,
            O::I32Ctz => Self::I32Ctz,
            O::I32Popcnt => Self::I32Popcnt,
            O::I32Add => Self::I32Add,
            O::I32Sub => Self::I32Sub,
            O::I32Mul => Self::I32Mul,
            O::I32DivS => Self::I32DivS,
            O::I32DivU => Self::I32DivU,
            O::I32RemS => Self::I32RemS,
            O::I32RemU => Self::I32RemU,
            O::I32And => Self::I32And,
            O::I32Or => Self::I32Or,
            O::I32Xor => Self::I32Xor,
            O::I32Shl => Self::I32Shl,
            O::I32ShrS => Self::I32ShrS,
            O::I32ShrU => Self::I32ShrU,
            O::I32Rotl => Self::I32Rotl,
            O::I32Rotr => Self::I32Rotr,
            O::I64Clz => Self::I64Clz,
            O::I64Ctz => Self::I64Ctz,
            O::I64Popcnt => Self::I64Popcnt,
            O::I64Add => Self::I64Add,
            O::I64Sub => Self::I64Sub,
            O::I64Mul => Self::I64Mul,
            O::I64DivS => Self::I64DivS,
            O::I64DivU => Self::I64DivU,
            O::I64RemS => Self::I64RemS,
            O::I64RemU => Self::I64RemU,
            O::I64And => Self::I64And,
            O::I64Or => Self::I64Or,
            O::I64Xor => Self::I64Xor,
            O::I64Shl => Self::I64Shl,
            O::I64ShrS => Self::I64ShrS,
            O::I64ShrU => Self::I64ShrU,
            O::I64Rotl => Self::I64Rotl,
            O::I64Rotr => Self::I64Rotr,
            O::F32Abs => Self::F32Abs,
            O::F32Neg => Self::F32Neg,
            O::F32Ceil => Self::F32Ceil,
            O::F32Floor => Self::F32Floor,
            O::F32Trunc => Self::F32Trunc,
            O::F32Nearest => Self::F32Nearest,
            O::F32Sqrt => Self::F32Sqrt,
            O::F32Add => Self::F32Add,
            O::F32Sub => Self::F32Sub,
            O::F32Mul => Self::F32Mul,
            O::F32Div => Self::F32Div,
            O::F32Min => Self::F32Min,
            O::F32Max => Self::F32Max,
            O::F32Copysign => Self::F32Copysign,
            O::F64Abs => Self::F64Abs,
            O::F64Neg => Self::F64Neg,
            O::F64Ceil => Self::F64Ceil,
            O::F64Floor => Self::F64Floor,
            O::F64Trunc => Self::F64Trunc,
            O::F64Nearest => Self::F64Nearest,
            O::F64Sqrt => Self::F64Sqrt,
            O::F64Add => Self::F64Add,
            O::F64Sub => Self::F64Sub,
            O::F64Mul => Self::F64Mul,
            O::F64Div => Self::F64Div,
            O::F64Min => Self::F64Min,
            O::F64Max => Self::F64Max,
            O::F64Copysign => Self::F64Copysign,
            O::I32WrapI64 => Self::I32WrapI64,
            O::I32TruncF32S => Self::I32TruncF32S,
            O::I32TruncF32U => Self::I32TruncF32U,
            O::I32TruncF64S => Self::I32TruncF64S,
            O::I32TruncF64U => Self::I32TruncF64U,
            O::I64ExtendI32S => Self::I64ExtendI32S,
            O::I64ExtendI32U => Self::I64ExtendI32U,
            O::I64TruncF32S => Self::I64TruncF32S,
            O::I64TruncF32U => Self::I64TruncF32U,
            O::I64TruncF64S => Self::I64TruncF64S,
            O::I64TruncF64U => Self::I64TruncF64U,
            O::F32ConvertI32S => Self::F32ConvertI32S,
            O::F32ConvertI32U => Self::F32ConvertI32U,
            O::F32ConvertI64S => Self::F32ConvertI64S,
            O::F32ConvertI64U => Self::F32ConvertI64U,
            O::F32DemoteF64 => Self::F32DemoteF64,
            O::F64ConvertI32S => Self::F64ConvertI32S,
            O::F64ConvertI32U => Self::F64ConvertI32U,
            O::F64ConvertI64S => Self::F64ConvertI64S,
            O::F64ConvertI64U => Self::F64ConvertI64U,
            O::F64PromoteF32 => Self::F64PromoteF32,
            O::I32ReinterpretF32 => Self::I32ReinterpretF32,
            O::I64ReinterpretF64 => Self::I64ReinterpretF64,
            O::F32ReinterpretI32 => Self::F32ReinterpretI32,
            O::F64ReinterpretI64 => Self::F64ReinterpretI64,
            O::I32Extend8S => Self::I32Extend8S,
            O::I32Extend16S => Self::I32Extend16S,
            O::I64Extend8S => Self::I64Extend8S,
            O::I64Extend16S => Self::I64Extend16S,
            O::I64Extend32S => Self::I64Extend32S,
            O::I32TruncSatF32S => Self::I32TruncSatF32S,
            O::I32TruncSatF32U => Self::I32TruncSatF32U,
            O::I32TruncSatF64S => Self::I32TruncSatF64S,
            O::I32TruncSatF64U => Self::I32TruncSatF64U,
            O::I64TruncSatF32S => Self::I64TruncSatF32S,
            O::I64TruncSatF32U => Self::I64TruncSatF32U,
            O::I64TruncSatF64S => Self::I64TruncSatF64S,
            O::I64TruncSatF64U => Self::I64TruncSatF64U,
            O::MemoryInit { .. } => Self::MemoryInit,
            O::DataDrop { .. } => Self::DataDrop,
            O::MemoryCopy { .. } => Self::MemoryCopy,
            O::MemoryFill { .. } => Self::MemoryFill,
            O::TableInit { .. } => Self::TableInit,
            O::ElemDrop { .. } => Self::ElemDrop,
            O::TableCopy { .. } => Self::TableCopy,
            O::TableFill { .. } => Self::TableFill,
            O::TableGet { .. } => Self::TableGet,
            O::TableSet { .. } => Self::TableSet,
            O::TableGrow { .. } => Self::TableGrow,
            O::TableSize { .. } => Self::TableSize,
            O::MemoryAtomicNotify { .. } => Self::MemoryAtomicNotify,
            O::MemoryAtomicWait32 { .. } => Self::MemoryAtomicWait32,
            O::MemoryAtomicWait64 { .. } => Self::MemoryAtomicWait64,
            O::AtomicFence { .. } => Self::AtomicFence,
            O::I32AtomicLoad { .. } => Self::I32AtomicLoad,
            O::I64AtomicLoad { .. } => Self::I64AtomicLoad,
            O::I32AtomicLoad8U { .. } => Self::I32AtomicLoad8U,
            O::I32AtomicLoad16U { .. } => Self::I32AtomicLoad16U,
            O::I64AtomicLoad8U { .. } => Self::I64AtomicLoad8U,
            O::I64AtomicLoad16U { .. } => Self::I64AtomicLoad16U,
            O::I64AtomicLoad32U { .. } => Self::I64AtomicLoad32U,
            O::I32AtomicStore { .. } => Self::I32AtomicStore,
            O::I64AtomicStore { .. } => Self::I64AtomicStore,
            O::I32AtomicStore8 { .. } => Self::I32AtomicStore8,
            O::I32AtomicStore16 { .. } => Self::I32AtomicStore16,
            O::I64AtomicStore8 { .. } => Self::I64AtomicStore8,
            O::I64AtomicStore16 { .. } => Self::I64AtomicStore16,
            O::I64AtomicStore32 { .. } => Self::I64AtomicStore32,
            O::I32AtomicRmwAdd { .. } => Self::I32AtomicRmwAdd,
            O::I64AtomicRmwAdd { .. } => Self::I64AtomicRmwAdd,
            O::I32AtomicRmw8AddU { .. } => Self::I32AtomicRmw8AddU,
            O::I32AtomicRmw16AddU { .. } => Self::I32AtomicRmw16AddU,
            O::I64AtomicRmw8AddU { .. } => Self::I64AtomicRmw8AddU,
            O::I64AtomicRmw16AddU { .. } => Self::I64AtomicRmw16AddU,
            O::I64AtomicRmw32AddU { .. } => Self::I64AtomicRmw32AddU,
            O::I32AtomicRmwSub { .. } => Self::I32AtomicRmwSub,
            O::I64AtomicRmwSub { .. } => Self::I64AtomicRmwSub,
            O::I32AtomicRmw8SubU { .. } => Self::I32AtomicRmw8SubU,
            O::I32AtomicRmw16SubU { .. } => Self::I32AtomicRmw16SubU,
            O::I64AtomicRmw8SubU { .. } => Self::I64AtomicRmw8SubU,
            O::I64AtomicRmw16SubU { .. } => Self::I64AtomicRmw16SubU,
            O::I64AtomicRmw32SubU { .. } => Self::I64AtomicRmw32SubU,
            O::I32AtomicRmwAnd { .. } => Self::I32AtomicRmwAnd,
            O::I64AtomicRmwAnd { .. } => Self::I64AtomicRmwAnd,
            O::I32AtomicRmw8AndU { .. } => Self::I32AtomicRmw8AndU,
            O::I32AtomicRmw16AndU { .. } => Self::I32AtomicRmw16AndU,
            O::I64AtomicRmw8AndU { .. } => Self::I64AtomicRmw8AndU,
            O::I64AtomicRmw16AndU { .. } => Self::I64AtomicRmw16AndU,
            O::I64AtomicRmw32AndU { .. } => Self::I64AtomicRmw32AndU,
            O::I32AtomicRmwOr { .. } => Self::I32AtomicRmwOr,
            O::I64AtomicRmwOr { .. } => Self::I64AtomicRmwOr,
            O::I32AtomicRmw8OrU { .. } => Self::I32AtomicRmw8OrU,
            O::I32AtomicRmw16OrU { .. } => Self::I32AtomicRmw16OrU,
            O::I64AtomicRmw8OrU { .. } => Self::I64AtomicRmw8OrU,
            O::I64AtomicRmw16OrU { .. } => Self::I64AtomicRmw16OrU,
            O::I64AtomicRmw32OrU { .. } => Self::I64AtomicRmw32OrU,
            O::I32AtomicRmwXor { .. } => Self::I32AtomicRmwXor,
            O::I64AtomicRmwXor { .. } => Self::I64AtomicRmwXor,
            O::I32AtomicRmw8XorU { .. } => Self::I32AtomicRmw8XorU,
            O::I32AtomicRmw16XorU { .. } => Self::I32AtomicRmw16XorU,
            O::I64AtomicRmw8XorU { .. } => Self::I64AtomicRmw8XorU,
            O::I64AtomicRmw16XorU { .. } => Self::I64AtomicRmw16XorU,
            O::I64AtomicRmw32XorU { .. } => Self::I64AtomicRmw32XorU,
            O::I32AtomicRmwXchg { .. } => Self::I32AtomicRmwXchg,
            O::I64AtomicRmwXchg { .. } => Self::I64AtomicRmwXchg,
            O::I32AtomicRmw8XchgU { .. } => Self::I32AtomicRmw8XchgU,
            O::I32AtomicRmw16XchgU { .. } => Self::I32AtomicRmw16XchgU,
            O::I64AtomicRmw8XchgU { .. } => Self::I64AtomicRmw8XchgU,
            O::I64AtomicRmw16XchgU { .. } => Self::I64AtomicRmw16XchgU,
            O::I64AtomicRmw32XchgU { .. } => Self::I64AtomicRmw32XchgU,
            O::I32AtomicRmwCmpxchg { .. } => Self::I32AtomicRmwCmpxchg,
            O::I64AtomicRmwCmpxchg { .. } => Self::I64AtomicRmwCmpxchg,
            O::I32AtomicRmw8CmpxchgU { .. } => Self::I32AtomicRmw8CmpxchgU,
            O::I32AtomicRmw16CmpxchgU { .. } => Self::I32AtomicRmw16CmpxchgU,
            O::I64AtomicRmw8CmpxchgU { .. } => Self::I64AtomicRmw8CmpxchgU,
            O::I64AtomicRmw16CmpxchgU { .. } => Self::I64AtomicRmw16CmpxchgU,
            O::I64AtomicRmw32CmpxchgU { .. } => Self::I64AtomicRmw32CmpxchgU,
            O::V128Load { .. } => Self::V128Load,
            O::V128Store { .. } => Self::V128Store,
            O::V128Const { .. } => Self::V128Const,
            O::I8x16Splat => Self::I8x16Splat,
            O::I8x16ExtractLaneS { .. } => Self::I8x16ExtractLaneS,
            O::I8x16ExtractLaneU { .. } => Self::I8x16ExtractLaneU,
            O::I8x16ReplaceLane { .. } => Self::I8x16ReplaceLane,
            O::I16x8Splat => Self::I16x8Splat,
            O::I16x8ExtractLaneS { .. } => Self::I16x8ExtractLaneS,
            O::I16x8ExtractLaneU { .. } => Self::I16x8ExtractLaneU,
            O::I16x8ReplaceLane { .. } => Self::I16x8ReplaceLane,
            O::I32x4Splat => Self::I32x4Splat,
            O::I32x4ExtractLane { .. } => Self::I32x4ExtractLane,
            O::I32x4ReplaceLane { .. } => Self::I32x4ReplaceLane,
            O::I64x2Splat => Self::I64x2Splat,
            O::I64x2ExtractLane { .. } => Self::I64x2ExtractLane,
            O::I64x2ReplaceLane { .. } => Self::I64x2ReplaceLane,
            O::F32x4Splat => Self::F32x4Splat,
            O::F32x4ExtractLane { .. } => Self::F32x4ExtractLane,
            O::F32x4ReplaceLane { .. } => Self::F32x4ReplaceLane,
            O::F64x2Splat => Self::F64x2Splat,
            O::F64x2ExtractLane { .. } => Self::F64x2ExtractLane,
            O::F64x2ReplaceLane { .. } => Self::F64x2ReplaceLane,
            O::I8x16Eq => Self::I8x16Eq,
            O::I8x16Ne => Self::I8x16Ne,
            O::I8x16LtS => Self::I8x16LtS,
            O::I8x16LtU => Self::I8x16LtU,
            O::I8x16GtS => Self::I8x16GtS,
            O::I8x16GtU => Self::I8x16GtU,
            O::I8x16LeS => Self::I8x16LeS,
            O::I8x16LeU => Self::I8x16LeU,
            O::I8x16GeS => Self::I8x16GeS,
            O::I8x16GeU => Self::I8x16GeU,
            O::I16x8Eq => Self::I16x8Eq,
            O::I16x8Ne => Self::I16x8Ne,
            O::I16x8LtS => Self::I16x8LtS,
            O::I16x8LtU => Self::I16x8LtU,
            O::I16x8GtS => Self::I16x8GtS,
            O::I16x8GtU => Self::I16x8GtU,
            O::I16x8LeS => Self::I16x8LeS,
            O::I16x8LeU => Self::I16x8LeU,
            O::I16x8GeS => Self::I16x8GeS,
            O::I16x8GeU => Self::I16x8GeU,
            O::I32x4Eq => Self::I32x4Eq,
            O::I32x4Ne => Self::I32x4Ne,
            O::I32x4LtS => Self::I32x4LtS,
            O::I32x4LtU => Self::I32x4LtU,
            O::I32x4GtS => Self::I32x4GtS,
            O::I32x4GtU => Self::I32x4GtU,
            O::I32x4LeS => Self::I32x4LeS,
            O::I32x4LeU => Self::I32x4LeU,
            O::I32x4GeS => Self::I32x4GeS,
            O::I32x4GeU => Self::I32x4GeU,
            O::I64x2Eq => Self::I64x2Eq,
            O::I64x2Ne => Self::I64x2Ne,
            O::I64x2LtS => Self::I64x2LtS,
            O::I64x2GtS => Self::I64x2GtS,
            O::I64x2LeS => Self::I64x2LeS,
            O::I64x2GeS => Self::I64x2GeS,
            O::F32x4Eq => Self::F32x4Eq,
            O::F32x4Ne => Self::F32x4Ne,
            O::F32x4Lt => Self::F32x4Lt,
            O::F32x4Gt => Self::F32x4Gt,
            O::F32x4Le => Self::F32x4Le,
            O::F32x4Ge => Self::F32x4Ge,
            O::F64x2Eq => Self::F64x2Eq,
            O::F64x2Ne => Self::F64x2Ne,
            O::F64x2Lt => Self::F64x2Lt,
            O::F64x2Gt => Self::F64x2Gt,
            O::F64x2Le => Self::F64x2Le,
            O::F64x2Ge => Self::F64x2Ge,
            O::V128Not => Self::V128Not,
            O::V128And => Self::V128And,
            O::V128AndNot => Self::V128AndNot,
            O::V128Or => Self::V128Or,
            O::V128Xor => Self::V128Xor,
            O::V128Bitselect => Self::V128Bitselect,
            O::V128AnyTrue => Self::V128AnyTrue,
            O::I8x16Popcnt => Self::I8x16Popcnt,
            O::I8x16Abs => Self::I8x16Abs,
            O::I8x16Neg => Self::I8x16Neg,
            O::I8x16AllTrue => Self::I8x16AllTrue,
            O::I8x16Bitmask => Self::I8x16Bitmask,
            O::I8x16Shl => Self::I8x16Shl,
            O::I8x16ShrS => Self::I8x16ShrS,
            O::I8x16ShrU => Self::I8x16ShrU,
            O::I8x16Add => Self::I8x16Add,
            O::I8x16AddSatS => Self::I8x16AddSatS,
            O::I8x16AddSatU => Self::I8x16AddSatU,
            O::I8x16Sub => Self::I8x16Sub,
            O::I8x16SubSatS => Self::I8x16SubSatS,
            O::I8x16SubSatU => Self::I8x16SubSatU,
            O::I8x16MinS => Self::I8x16MinS,
            O::I8x16MinU => Self::I8x16MinU,
            O::I8x16MaxS => Self::I8x16MaxS,
            O::I8x16MaxU => Self::I8x16MaxU,
            O::I16x8Abs => Self::I16x8Abs,
            O::I16x8Neg => Self::I16x8Neg,
            O::I16x8AllTrue => Self::I16x8AllTrue,
            O::I16x8Bitmask => Self::I16x8Bitmask,
            O::I16x8Shl => Self::I16x8Shl,
            O::I16x8ShrS => Self::I16x8ShrS,
            O::I16x8ShrU => Self::I16x8ShrU,
            O::I16x8Add => Self::I16x8Add,
            O::I16x8AddSatS => Self::I16x8AddSatS,
            O::I16x8AddSatU => Self::I16x8AddSatU,
            O::I16x8Sub => Self::I16x8Sub,
            O::I16x8SubSatS => Self::I16x8SubSatS,
            O::I16x8SubSatU => Self::I16x8SubSatU,
            O::I16x8Mul => Self::I16x8Mul,
            O::I16x8MinS => Self::I16x8MinS,
            O::I16x8MinU => Self::I16x8MinU,
            O::I16x8MaxS => Self::I16x8MaxS,
            O::I16x8MaxU => Self::I16x8MaxU,
            O::I16x8ExtAddPairwiseI8x16S => Self::I16x8ExtAddPairwiseI8x16S,
            O::I16x8ExtAddPairwiseI8x16U => Self::I16x8ExtAddPairwiseI8x16U,
            O::I32x4Abs => Self::I32x4Abs,
            O::I32x4Neg => Self::I32x4Neg,
            O::I32x4AllTrue => Self::I32x4AllTrue,
            O::I32x4Bitmask => Self::I32x4Bitmask,
            O::I32x4Shl => Self::I32x4Shl,
            O::I32x4ShrS => Self::I32x4ShrS,
            O::I32x4ShrU => Self::I32x4ShrU,
            O::I32x4Add => Self::I32x4Add,
            O::I32x4Sub => Self::I32x4Sub,
            O::I32x4Mul => Self::I32x4Mul,
            O::I32x4MinS => Self::I32x4MinS,
            O::I32x4MinU => Self::I32x4MinU,
            O::I32x4MaxS => Self::I32x4MaxS,
            O::I32x4MaxU => Self::I32x4MaxU,
            O::I32x4DotI16x8S => Self::I32x4DotI16x8S,
            O::I32x4ExtAddPairwiseI16x8S => Self::I32x4ExtAddPairwiseI16x8S,
            O::I32x4ExtAddPairwiseI16x8U => Self::I32x4ExtAddPairwiseI16x8U,
            O::I64x2Abs => Self::I64x2Abs,
            O::I64x2Neg => Self::I64x2Neg,
            O::I64x2AllTrue => Self::I64x2AllTrue,
            O::I64x2Bitmask => Self::I64x2Bitmask,
            O::I64x2Shl => Self::I64x2Shl,
            O::I64x2ShrS => Self::I64x2ShrS,
            O::I64x2ShrU => Self::I64x2ShrU,
            O::I64x2Add => Self::I64x2Add,
            O::I64x2Sub => Self::I64x2Sub,
            O::I64x2Mul => Self::I64x2Mul,
            O::F32x4Ceil => Self::F32x4Ceil,
            O::F32x4Floor => Self::F32x4Floor,
            O::F32x4Trunc => Self::F32x4Trunc,
            O::F32x4Nearest => Self::F32x4Nearest,
            O::F64x2Ceil => Self::F64x2Ceil,
            O::F64x2Floor => Self::F64x2Floor,
            O::F64x2Trunc => Self::F64x2Trunc,
            O::F64x2Nearest => Self::F64x2Nearest,
            O::F32x4Abs => Self::F32x4Abs,
            O::F32x4Neg => Self::F32x4Neg,
            O::F32x4Sqrt => Self::F32x4Sqrt,
            O::F32x4Add => Self::F32x4Add,
            O::F32x4Sub => Self::F32x4Sub,
            O::F32x4Mul => Self::F32x4Mul,
            O::F32x4Div => Self::F32x4Div,
            O::F32x4Min => Self::F32x4Min,
            O::F32x4Max => Self::F32x4Max,
            O::F32x4PMin => Self::F32x4PMin,
            O::F32x4PMax => Self::F32x4PMax,
            O::F64x2Abs => Self::F64x2Abs,
            O::F64x2Neg => Self::F64x2Neg,
            O::F64x2Sqrt => Self::F64x2Sqrt,
            O::F64x2Add => Self::F64x2Add,
            O::F64x2Sub => Self::F64x2Sub,
            O::F64x2Mul => Self::F64x2Mul,
            O::F64x2Div => Self::F64x2Div,
            O::F64x2Min => Self::F64x2Min,
            O::F64x2Max => Self::F64x2Max,
            O::F64x2PMin => Self::F64x2PMin,
            O::F64x2PMax => Self::F64x2PMax,
            O::I32x4TruncSatF32x4S => Self::I32x4TruncSatF32x4S,
            O::I32x4TruncSatF32x4U => Self::I32x4TruncSatF32x4U,
            O::F32x4ConvertI32x4S => Self::F32x4ConvertI32x4S,
            O::F32x4ConvertI32x4U => Self::F32x4ConvertI32x4U,
            O::I8x16Swizzle => Self::I8x16Swizzle,
            O::I8x16Shuffle { .. } => Self::I8x16Shuffle,
            O::V128Load8Splat { .. } => Self::V128Load8Splat,
            O::V128Load16Splat { .. } => Self::V128Load16Splat,
            O::V128Load32Splat { .. } => Self::V128Load32Splat,
            O::V128Load32Zero { .. } => Self::V128Load32Zero,
            O::V128Load64Splat { .. } => Self::V128Load64Splat,
            O::V128Load64Zero { .. } => Self::V128Load64Zero,
            O::I8x16NarrowI16x8S => Self::I8x16NarrowI16x8S,
            O::I8x16NarrowI16x8U => Self::I8x16NarrowI16x8U,
            O::I16x8NarrowI32x4S => Self::I16x8NarrowI32x4S,
            O::I16x8NarrowI32x4U => Self::I16x8NarrowI32x4U,
            O::I16x8ExtendLowI8x16S => Self::I16x8ExtendLowI8x16S,
            O::I16x8ExtendHighI8x16S => Self::I16x8ExtendHighI8x16S,
            O::I16x8ExtendLowI8x16U => Self::I16x8ExtendLowI8x16U,
            O::I16x8ExtendHighI8x16U => Self::I16x8ExtendHighI8x16U,
            O::I32x4ExtendLowI16x8S => Self::I32x4ExtendLowI16x8S,
            O::I32x4ExtendHighI16x8S => Self::I32x4ExtendHighI16x8S,
            O::I32x4ExtendLowI16x8U => Self::I32x4ExtendLowI16x8U,
            O::I32x4ExtendHighI16x8U => Self::I32x4ExtendHighI16x8U,
            O::I64x2ExtendLowI32x4S => Self::I64x2ExtendLowI32x4S,
            O::I64x2ExtendHighI32x4S => Self::I64x2ExtendHighI32x4S,
            O::I64x2ExtendLowI32x4U => Self::I64x2ExtendLowI32x4U,
            O::I64x2ExtendHighI32x4U => Self::I64x2ExtendHighI32x4U,
            O::I16x8ExtMulLowI8x16S => Self::I16x8ExtMulLowI8x16S,
            O::I16x8ExtMulHighI8x16S => Self::I16x8ExtMulHighI8x16S,
            O::I16x8ExtMulLowI8x16U => Self::I16x8ExtMulLowI8x16U,
            O::I16x8ExtMulHighI8x16U => Self::I16x8ExtMulHighI8x16U,
            O::I32x4ExtMulLowI16x8S => Self::I32x4ExtMulLowI16x8S,
            O::I32x4ExtMulHighI16x8S => Self::I32x4ExtMulHighI16x8S,
            O::I32x4ExtMulLowI16x8U => Self::I32x4ExtMulLowI16x8U,
            O::I32x4ExtMulHighI16x8U => Self::I32x4ExtMulHighI16x8U,
            O::I64x2ExtMulLowI32x4S => Self::I64x2ExtMulLowI32x4S,
            O::I64x2ExtMulHighI32x4S => Self::I64x2ExtMulHighI32x4S,
            O::I64x2ExtMulLowI32x4U => Self::I64x2ExtMulLowI32x4U,
            O::I64x2ExtMulHighI32x4U => Self::I64x2ExtMulHighI32x4U,
            O::V128Load8x8S { .. } => Self::V128Load8x8S,
            O::V128Load8x8U { .. } => Self::V128Load8x8U,
            O::V128Load16x4S { .. } => Self::V128Load16x4S,
            O::V128Load16x4U { .. } => Self::V128Load16x4U,
            O::V128Load32x2S { .. } => Self::V128Load32x2S,
            O::V128Load32x2U { .. } => Self::V128Load32x2U,
            O::V128Load8Lane { .. } => Self::V128Load8Lane,
            O::V128Load16Lane { .. } => Self::V128Load16Lane,
            O::V128Load32Lane { .. } => Self::V128Load32Lane,
            O::V128Load64Lane { .. } => Self::V128Load64Lane,
            O::V128Store8Lane { .. } => Self::V128Store8Lane,
            O::V128Store16Lane { .. } => Self::V128Store16Lane,
            O::V128Store32Lane { .. } => Self::V128Store32Lane,
            O::V128Store64Lane { .. } => Self::V128Store64Lane,
            O::I8x16AvgrU => Self::I8x16RoundingAverageU,
            O::I16x8AvgrU => Self::I16x8RoundingAverageU,
            O::I16x8Q15MulrSatS => Self::I16x8Q15MulrSatS,
            O::F32x4DemoteF64x2Zero => Self::F32x4DemoteF64x2Zero,
            O::F64x2PromoteLowF32x4 => Self::F64x2PromoteLowF32x4,
            O::F64x2ConvertLowI32x4S => Self::F64x2ConvertLowI32x4S,
            O::F64x2ConvertLowI32x4U => Self::F64x2ConvertLowI32x4U,
            O::I32x4TruncSatF64x2SZero => Self::I32x4TruncSatF64x2SZero,
            O::I32x4TruncSatF64x2UZero => Self::I32x4TruncSatF64x2UZero,
            O::I8x16RelaxedSwizzle => Self::I8x16RelaxedSwizzle,
            O::I32x4RelaxedTruncSatF32x4S => Self::I32x4RelaxedTruncSatF32x4S,
            O::I32x4RelaxedTruncSatF32x4U => Self::I32x4RelaxedTruncSatF32x4U,
            O::I32x4RelaxedTruncSatF64x2SZero => Self::I32x4RelaxedTruncSatF64x2SZero,
            O::I32x4RelaxedTruncSatF64x2UZero => Self::I32x4RelaxedTruncSatF64x2UZero,
            O::F32x4RelaxedFma => Self::F32x4Fma,
            O::F32x4RelaxedFnma => Self::F32x4Fms,
            O::F64x2RelaxedFma => Self::F64x2Fma,
            O::F64x2RelaxedFnma => Self::F64x2Fms,
            O::I8x16RelaxedLaneselect => Self::I8x16LaneSelect,
            O::I16x8RelaxedLaneselect => Self::I16x8LaneSelect,
            O::I32x4RelaxedLaneselect => Self::I32x4LaneSelect,
            O::I64x2RelaxedLaneselect => Self::I64x2LaneSelect,
            O::F32x4RelaxedMin => Self::F32x4RelaxedMin,
            O::F32x4RelaxedMax => Self::F32x4RelaxedMax,
            O::F64x2RelaxedMin => Self::F64x2RelaxedMin,
            O::F64x2RelaxedMax => Self::F64x2RelaxedMax,
            O::I16x8RelaxedQ15mulrS => Self::I16x8RelaxedQ15mulrS,
            O::I16x8DotI8x16I7x16S => Self::I16x8DotI8x16I7x16S,
            O::I32x4DotI8x16I7x16AddS => Self::I32x4DotI8x16I7x16AddS,
            O::F32x4RelaxedDotBf16x8AddF32x4 => Self::F32x4RelaxedDotBf16x8AddF32x4,
        }
    }
}
