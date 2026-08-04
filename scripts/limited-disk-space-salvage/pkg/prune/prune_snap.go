package prune

import (
	"errors"
	"fmt"
	"os"

	"github.com/longhorn/longhorn/scripts/limited-disk-space-salvage/pkg/sectormap"
	"github.com/longhorn/sparse-tools/sparse"
	"github.com/sirupsen/logrus"
)

// PunchSnapshots for every sector range with a resolved owner, it punches a hole for that range in
// every ancestor of the owner. Sectors with no resolved owner are left untouched.
func PunchSnapshots(location []byte, names []string, totalSectors int64, sectorSize int64, diskMetas sectormap.MetaFileMap, dryRun bool) error {
	if totalSectors == 0 {
		return nil
	}

	punchRun := func(runStart, runEnd int64, ownerIdx byte) error {
		if ownerIdx == 0 {
			// Implicitly owned by the base/oldest layer, nothing newer shadows it, nothing to punch.
			return nil
		}

		ownerName := names[ownerIdx]
		ancestors, err := diskMetas.AncestorsOf(ownerName)
		if err != nil {
			if errors.Is(err, sectormap.ErrMetaNotFound) {
				// e.g. owner is the oldest snapshot, or a base image with no
				// .meta -- nothing older exists, so nothing to punch.
				logrus.Warnf("no metadata for %v; skipping punch for sectors [%d,%d)", ownerName, runStart, runEnd)
				return nil
			}
			return fmt.Errorf("failed to get ancestors of %v: %w", ownerName, err)
		}
		if len(ancestors) == 0 {
			return nil
		}

		offset := runStart * sectorSize
		length := (runEnd - runStart) * sectorSize

		for _, ancestor := range ancestors {
			if dryRun {
				fmt.Printf("[dry-run] would punch %v at offset=%d length=%d (owner=%v, sectors=[%d,%d))\n",
					ancestor, offset, length, ownerName, runStart, runEnd)
				continue
			}

			fileIo, err := sparse.NewDirectFileIoProcessor(ancestor, os.O_RDWR, 0)
			if err != nil {
				return fmt.Errorf("failed to open ancestor %v: %w", ancestor, err)
			}

			fiemapFile := sparse.NewFiemapFile(fileIo.GetFile())
			punchErr := fiemapFile.PunchHole(offset, length)
			closeErr := fileIo.Close()

			if punchErr != nil {
				return fmt.Errorf("failed to punch hole in %v at [%d,+%d): %w",
					ancestor, offset, length, punchErr)
			}
			if closeErr != nil {
				return fmt.Errorf("failed to close %v: %w", ancestor, closeErr)
			}
			logrus.Infof("punched %v at [%d,+%d]", ancestor, offset, length)
		}
		return nil
	}

	runStart := int64(0)
	runOwnerIdx := sectormap.OwnerIndex(location, 0)

	for s := int64(1); s < totalSectors; s++ {
		idx := sectormap.OwnerIndex(location, s)
		if idx != runOwnerIdx {
			if err := punchRun(runStart, s, runOwnerIdx); err != nil {
				return err
			}
			runStart, runOwnerIdx = s, idx
		}
	}

	return punchRun(runStart, totalSectors, runOwnerIdx)
}
