package sectormap

import (
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"github.com/longhorn/longhorn-engine/pkg/types"
)

var ErrMetaNotFound = errors.New("meta file not found")

type VolumeMeta struct {
	Size            int64  `json:"Size"`
	Head            string `json:"Head"`
	Dirty           bool   `json:"Dirty"`
	Parent          string `json:"Parent"`
	SectorSize      int64  `json:"SectorSize"`
	BackingFileName string `json:"BackingFileName"`
}

type MetaFileMap map[string]types.DiskInfo

// LoadVolumeMeta reads and parses volume.meta from the replica dir.
func LoadVolumeMeta(dir string) (VolumeMeta, error) {
	var vm VolumeMeta
	data, err := os.ReadFile(filepath.Join(dir, "volume.meta"))
	if err != nil {
		return vm, fmt.Errorf("failed to read volume.meta: %w", err)
	}
	if err := json.Unmarshal(data, &vm); err != nil {
		return vm, fmt.Errorf("failed to unmarshal volume.meta: %w", err)
	}
	return vm, nil
}

// LoadDiskMetas loops through *.meta files in dir (skipping volume.meta, as is
// handled by loadVolumeMeta), unmarshals each into a types.DiskInfo, and
// returns a MetaFileMap keyed by the meta file's base name.
func LoadDiskMetas(dir string) (MetaFileMap, error) {
	metaFiles, err := filepath.Glob(filepath.Join(dir, "*.meta"))
	if err != nil {
		return nil, fmt.Errorf("failed to glob *.meta files in %s: %w", dir, err)
	}

	metas := make(MetaFileMap)
	for _, metaFile := range metaFiles {
		// volume.meta is handled by LoadVolumeMeta
		if strings.HasSuffix(metaFile, "volume.meta") {
			continue
		}
		data, err := os.ReadFile(metaFile)
		if err != nil {
			return nil, fmt.Errorf("failed to read file %s: %v", metaFile, err)
		}
		var metaData types.DiskInfo
		if err := json.Unmarshal(data, &metaData); err != nil {
			return nil, fmt.Errorf("failed to unmarshal meta file %s: %v", metaFile, err)
		}
		metas[filepath.Base(metaFile)] = metaData
	}

	return metas, nil
}

// OrderChain walks the disk chain starting at volume-head-*.meta, following each
// meta's Parent link, and returns the chain as a slice of file names ordered
// from newest (head) to oldest.
func (metas MetaFileMap) OrderChain(headMetaFile string) ([]string, error) {
	var newestToOldest []string

	curr, ok := metas[headMetaFile]
	if !ok {
		return nil, fmt.Errorf("head %s not found", headMetaFile)
	}
	for {
		newestToOldest = append(newestToOldest, curr.Name)

		// TODO: check for curr.Removed scenario
		//if curr.Removed {
		//	fmt.Printf("warning: %s is marked removed; verify the disk file still exists\n", curr.Name)
		//}

		if curr.Parent == "" {
			break
		}
		next, ok := metas[curr.Parent+".meta"]
		if !ok {
			return nil, fmt.Errorf("parent %s referenced by %s but missing", curr.Parent, curr.Name)
		}
		curr = next
	}

	return newestToOldest, nil
}

// AncestorsOf returns [parent, grandparent, ...] for any meta file.
func (metas MetaFileMap) AncestorsOf(diskFileName string) ([]string, error) {
	if diskFileName == "" {
		return nil, fmt.Errorf("empty disk file name passed to AncestorsOf")
	}

	headMetaFile := diskFileName + ".meta"
	if _, ok := metas[headMetaFile]; !ok {
		// No metadata for this file at all -- most likely it's the
		// oldest snapshot / base layer (nothing points further back),
		// or a backing image (which never has a .meta). Either way,
		// there's nothing "older" to punch. Not an error.
		return nil, ErrMetaNotFound
	}

	chain, err := metas.OrderChain(headMetaFile)
	if err != nil {
		return nil, fmt.Errorf("failed to build chain for %v: %w", diskFileName, err)
	}
	if len(chain) <= 1 {
		return nil, nil
	}
	return chain[1:], nil
}

// OwnerIndex returns the raw index stored at this sector: 0 means
// unresolved (implicitly owned by the oldest/base layer), non-zero means
// an explicit owner was found via extents.
func OwnerIndex(location []byte, sector int64) byte {
	return location[sector]
}
