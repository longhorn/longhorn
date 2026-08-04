package sectormap

import (
	"fmt"
	"os"
)

// DumpExtents prints the raw FIEMAP extents for each layer, before any
// of it gets folded into the location[] table. Use this to see whether
// fragmentation is real (many small extents) or whether the location[]
// table/print loop is the problem (few large extents, but tiny printed
// ranges).
func DumpExtents(newestToOldest []string, fileByName LayerFileMap, backingFileName string, totalSectors int64) error {
	if backingFileName != "" {
		f, ok := fileByName[backingFileName]
		if !ok {
			return fmt.Errorf("no open file for backing file %s", backingFileName)
		}
		if err := dumpExtentsForFile(backingFileName, f, totalSectors); err != nil {
			return err
		}
	}

	for _, fName := range newestToOldest {
		f, ok := fileByName[fName]
		if !ok {
			return fmt.Errorf("no open file for %s", fName)
		}
		if err := dumpExtentsForFile(fName, f, totalSectors); err != nil {
			return err
		}
	}
	return nil
}

func dumpExtentsForFile(name string, f *os.File, totalSectors int64) error {
	extents, err := getAllExtents(f, uint64(totalSectors)*sectorSize)
	if err != nil {
		return fmt.Errorf("failed to read extents for %s: %w", name, err)
	}
	fmt.Printf("=== %s: %d extents ===\n", name, len(extents))
	for _, e := range extents {
		startSector := int64(e.Logical) / sectorSize
		lengthSectors := int64(e.Length) / sectorSize
		fmt.Printf("  logical=%d length=%d  -> sectors [%d, %d)\n",
			e.Logical, e.Length, startSector, startSector+lengthSectors)
	}
	return nil
}

// PrintSectorRanges walks the resolved location[] table and prints
// collapsed [start,end): owner ranges instead of one line per sector.
// This is the view you actually want to eyeball for correctness.
func PrintSectorRanges(location []byte, names []string, totalSectors int64, fallbackName string) {
	if totalSectors == 0 {
		return
	}

	runStart := int64(0)
	runOwner := Owner(location, names, 0, fallbackName)

	for s := int64(1); s < totalSectors; s++ {
		owner := Owner(location, names, s, fallbackName)
		if owner != runOwner {
			fmt.Printf("[%d, %d): %s  (%d sectors)\n", runStart, s, runOwner, s-runStart)
			runStart, runOwner = s, owner
		}
	}
	fmt.Printf("[%d, %d): %s  (%d sectors)\n", runStart, totalSectors, runOwner, totalSectors-runStart)
}

// Owner resolves a sector to its owning filename. Sectors nobody ever
// wrote to (still sectorNil after the loop above) fall back to
// fallbackName -- pass the backing file's name if present, else head's.
func Owner(location []byte, names []string, sector int64, fallbackName string) string {
	idx := location[sector]
	if idx == sectorNil {
		return fallbackName
	}
	return names[idx]
}
