package main

import (
	"encoding/json"
	"fmt"
	"io/ioutil"

	"github.com/spf13/cobra"
	"github.com/cosmos/cosmos-sdk/server"
	genutiltypes "github.com/cosmos/cosmos-sdk/x/genutil/types"
	fsmtypes "github.com/engram-network/striatum-core/x/fsm/types"
)

// AddFSMParamsCmd trả về lệnh CLI 'stratiumd add-fsm-params'
func AddFSMParamsCmd() *cobra.Command {
	cmd := &cobra.Command{
		Use:   "add-fsm-params [genesis-file]",
		Short: "Injects mathematical FSM thresholds (T1=100, T2=500) into genesis.json",
		Args:  cobra.ExactArgs(1),
		RunE: func(cmd *cobra.Command, args []string) error {
			genesisFile := args
			
			// 1. Đọc file genesis.json hiện tại
			appState, genDoc, err := genutiltypes.GenesisStateFromGenFile(genesisFile)
			if err != nil {
				return fmt.Errorf("failed to unmarshal genesis state: %w", err)
			}

			// 2. Khởi tạo tham số FSM chuẩn theo Sách trắng Engram [4]
			fsmGenState := fsmtypes.DefaultGenesis()
			fsmGenState.Params.ThresholdSuspicious = 100 // T1: Chuyển sang SUSPICIOUS [3, 4]
			fsmGenState.Params.ThresholdSovereign = 500  // T2: Chuyển sang SOVEREIGN (Kích hoạt Fallback) [3, 4]
			fsmGenState.Params.CheckInterval = 10        // Lấy mẫu mỗi 10 giây [4]

			// 3. Ghi đè vào AppState
			fsmGenStateBz, err := json.Marshal(fsmGenState)
			if err != nil {
				return err
			}
			appState[fsmtypes.ModuleName] = fsmGenStateBz

			// 4. Lưu lại file genesis.json
			appStateJSON, err := json.Marshal(appState)
			if err != nil {
				return err
			}
			genDoc.AppState = appStateJSON
			return genutiltypes.ExportGenesisFile(genDoc, genesisFile)
		},
	}
	return cmd
}