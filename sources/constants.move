module fenture::constants {
    use aptos_std::math128::pow;

    public fun Exp_Scale(): u128 { pow(10, 16) }
    public fun Double_Scale(): u128 { Exp_Scale() * Exp_Scale() }
    public fun Half_Scale():u128 { Exp_Scale() / 2 }
    public fun Mantissa_One(): u128 { Exp_Scale() }
    public fun Borrow_Rate_Max_Mantissa(): u128 { 5000000000 * Exp_Scale() / pow(10, 16) }
    public fun Reserve_Factor_Max_Mantissa(): u128 { Exp_Scale() }

    public fun Fenture_Claim_Threshold(): u128 { pow(10,6) } // 0.01
    public fun Fenture_Initial_Index(): u128 { Exp_Scale() } // 1

    public fun Close_Factor_Min_Mantissa(): u128 { 5 * Exp_Scale() / pow(10, 2) } // 0.05
    public fun Close_Factor_Max_Mantissa(): u128 { 9 * Exp_Scale() / pow(10, 1) } // 0.9
    public fun Close_Factor_Default_Mantissa(): u128 { 5 * Exp_Scale() / pow(10, 1) } // 0.5

    public fun Collateral_Factor_Max_Mantissa(): u128 { 9 * Exp_Scale() / pow(10, 1) } // 0.9
    public fun Collateral_Factor_Default_Mantissa(): u128 { 0 } // 0

    public fun Liquidation_Incentive_Min_Mantissa(): u128 { Exp_Scale() } // 1.0
    public fun Liquidation_Incentive_Max_Mantissa(): u128 { 15 * Exp_Scale() / pow(10, 1) } // 1.5
    public fun Liquidation_Incentive_Default_Mantissa(): u128 { 108 * Exp_Scale() / pow(10, 2) } // 1.08

}