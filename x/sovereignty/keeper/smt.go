package keeper

import (
	"log"

	badger "github.com/dgraph-io/badger/v4"
	"github.com/iden3/go-merkletree-sql/v2"
	"github.com/iden3/go-merkletree-sql/v2/db/badgerdb"
)

type SovereignSMT struct {
	badgerDB *badger.DB
	tree     *merkletree.MerkleTree
}

func InitSMT(dbPath string) (*SovereignSMT, error) {
	opts := badger.DefaultOptions(dbPath)
	opts.Logger = nil
	db, err := badger.Open(opts)
	if err != nil {
		return nil, err
	}

	store := badgerdb.NewStorage(db)

	tree, err := merkletree.NewMerkleTree(ctx, store, 256)
	if err != nil {
		return nil, err
	}

	return &SovereignSMT{
		badgerDB: db,
		tree:     tree,
	}, nil
}

func (s *SovereignSMT) Close() {
	if s.badgerDB != nil {
		s.badgerDB.Close()
	}
}

func (s *SovereignSMT) AddState(ctx context.Context, key []byte, value []byte) error {
	return s.tree.Add(ctx, key, value)
}


func (s *SovereignSMT) GetRoot() []byte {
	return s.tree.Root().Bytes()
}