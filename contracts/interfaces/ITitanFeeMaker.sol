pragma solidity >=0.5.0;

interface ITitanFeeMaker {
    function depositLp(address _lpToken,uint256 _amount) external;
    function withdrawLp(address _lpToken,uint256 _amount) external;

    function withdrawETH(address to) external;
    function withdrawUSDT(address to) external;
    function withdrawTitan(uint256 amount) external;

    function chargeTitan(uint256 amount) external;
    function adjustTitanBonus(uint256 _BONUS_MULTIPLIER) external;
}