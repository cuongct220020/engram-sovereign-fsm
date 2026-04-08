package keeper

import (
    "github.com/cosmos/cosmos-sdk/codec"
    storetypes "github.com/cosmos/cosmos-sdk/store/types"
    dakeeper "engram/x/da/keeper"
    vigilantekeeper "engram/x/vigilante/keeper"
)

type Keeper struct {
    cdc             codec.BinaryCodec
    storeKey        storetypes.StoreKey
    
    // Injected Sensor Modules
    daKeeper        dakeeper.Keeper
    vigilanteKeeper vigilantekeeper.Keeper
	
	StateTree       *SovereignSMT
}

func NewKeeper(cdc codec.BinaryCodec, key storetypes.StoreKey, daK dakeeper.Keeper, vigK vigilantekeeper.Keeper) Keeper {

	smt, err := InitSMT(smtPath)
	if err != nil {
		panic("Not initialization SMT BadgerDB: " + err.Error())
	}

	return Keeper{
		cdc:             cdc,
		storeKey:        key,
		daKeeper:        daK,
		vigilanteKeeper: vigK,
		StateTree:       smt,
	}
}