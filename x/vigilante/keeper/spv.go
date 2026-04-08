import (
    babylonspv "github.com/babylonchain/babylon/x/btclightclient/types"
    babylonschnorr "github.com/babylonchain/babylon/crypto/schnorr"
)


func VerifyBitcoinProof(btcHeader []byte, proof []byte) bool {
    header, err := babylonspv.ParseBitcoinHeader(btcHeader)
    if err != nil {
        return false
    }
    
    return babylonschnorr.Verify(header.Hash, proof)
}