package sectormap

import (
	"fmt"
	"os"

	"github.com/rancher/go-fibmap"
)

const sectorNil = byte(0)

func BuildSectorLocationMap(newestToOldest []string, fileByName LayerFileMap, backingFileName string, totalSectors int64) (location []byte, names []string, err error) {
	if len(newestToOldest) == 0 {
		return nil, nil, fmt.Errorf("no layers provided")
	}
	if len(newestToOldest) > 254 {
		// byte can hold indices 1-255; Longhorn caps chains well below this anyway
		return nil, nil, fmt.Errorf("chain too long for a byte index: %d layers", len(newestToOldest))
	}

	location = make([]byte, totalSectors) // zero-value = sectorNil
	names = []string{"", backingFileName} // index 0 = reserved, index 1 = backing (possibly "")

	nextIndex := byte(2)
	remaining := totalSectors

	for _, fName := range newestToOldest {
		idx := nextIndex
		names = append(names, fName)
		nextIndex++

		if remaining == 0 {
			continue // still need to record the name, just nothing left to resolve
		}

		file, ok := fileByName[fName]
		if !ok {
			return nil, nil, fmt.Errorf("no open file for %s", fName)
		}

		extents, err := getAllExtents(file, uint64(totalSectors)*sectorSize)
		if err != nil {
			return nil, nil, fmt.Errorf("failed to read extents for %s: %w", fName, err)
		}

		for _, extent := range extents {
			startSector := int64(extent.Logical) / sectorSize
			endSector := (int64(extent.Logical) + int64(extent.Length)) / sectorSize
			if endSector > totalSectors {
				endSector = totalSectors
			}
			for s := startSector; s < endSector; s++ {
				if location[s] == 0 {
					// enters only when unclaimed
					location[s] = idx
					remaining--
				}
			}
		}
	}

	return location, names, nil
}

// getAllExtents pulls the complete FIEMAP extent list for a file, paging
// through multiple ioctl calls if needed.
func getAllExtents(f *os.File, length uint64) ([]fibmap.Extent, error) {
	var all []fibmap.Extent
	start := uint64(0)

	for {
		extents, errno := fibmap.Fiemap(f.Fd(), start, length-start, maxExtentsPerCall)
		if errno != 0 {
			return nil, fmt.Errorf("fiemap errno: %v", errno)
		}
		if len(extents) == 0 {
			return all, nil
		}
		all = append(all, extents...)

		last := extents[len(extents)-1]
		if last.Flags&fibmap.FIEMAP_EXTENT_LAST != 0 {
			return all, nil
		}
		start = last.Logical + last.Length
	}
}
