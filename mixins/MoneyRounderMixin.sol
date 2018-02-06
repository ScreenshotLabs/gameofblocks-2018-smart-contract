pragma solidity ^0.4.11;

/// @title Mixin to help make nicer looking ether amounts.
contract MoneyRounderMixin {

    /// @notice Make `_rawValueWei` into a nicer, rounder number.
    /// @return A value that:
    ///   - is no larger than `_rawValueWei`
    ///   - is no smaller than `_rawValueWei` * 0.999
    ///   - has no more than three significant figures UNLESS the
    ///     number is very small or very large in monetary terms
    ///     (which we define as < 1 finney or > 10000 ether), in
    ///     which case no precision will be lost.
    function roundMoneyDownNicely(uint _rawValueWei) constant internal
    returns (uint nicerValueWei) {
        if (_rawValueWei < 1 finney) {
            return _rawValueWei;
        } else if (_rawValueWei < 10 finney) {
            return 10 szabo * (_rawValueWei / 10 szabo);
        } else if (_rawValueWei < 100 finney) {
            return 100 szabo * (_rawValueWei / 100 szabo);
        } else if (_rawValueWei < 1 ether) {
            return 1 finney * (_rawValueWei / 1 finney);
        } else if (_rawValueWei < 10 ether) {
            return 10 finney * (_rawValueWei / 10 finney);
        } else if (_rawValueWei < 100 ether) {
            return 100 finney * (_rawValueWei / 100 finney);
        } else if (_rawValueWei < 1000 ether) {
            return 1 ether * (_rawValueWei / 1 ether);
        } else if (_rawValueWei < 10000 ether) {
            return 10 ether * (_rawValueWei / 10 ether);
        } else {
            return _rawValueWei;
        }
    }
    
    /// @notice Convert `_valueWei` into a whole number of finney.
    /// @return The smallest whole number of finney which is equal
    /// to or greater than `_valueWei` when converted to wei.
    /// WARN: May be incorrect if `_valueWei` is above 2**254.
    // function roundMoneyUpToWholeFinney(uint _valueWei) constant internal
    // returns (uint valueFinney) {
    //     return (1 finney + _valueWei - 1 wei) / 1 finney;
    // }

}