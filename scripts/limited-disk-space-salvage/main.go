package main

import (
	"bufio"
	"fmt"
	"os"
	"strings"

	"github.com/longhorn/longhorn/scripts/limited-disk-space-salvage/pkg/prune"
	"github.com/longhorn/longhorn/scripts/limited-disk-space-salvage/pkg/sectormap"
)

var replicaDir = os.Getenv("REPLICA_DIR")

func main() {
	volMeta, err := sectormap.LoadVolumeMeta(replicaDir)
	if err != nil {
		panic(err)
	}

	headMetaFile := volMeta.Head + ".meta"
	diskMetas, err := sectormap.LoadDiskMetas(replicaDir)
	if err != nil {
		panic(err)
	}

	orderedChain, err := diskMetas.OrderChain(headMetaFile)
	if err != nil {
		panic(err)
	}

	os.Chdir(replicaDir)
	fileByName, err := sectormap.OpenLayers(orderedChain, os.O_RDWR)
	if err != nil {
		panic(err)
	}
	defer fileByName.Close()

	backingFileName := volMeta.BackingFileName
	if backingFileName != "" {
		bf, err := os.Open(backingFileName) // read-only, never punched/written
		if err != nil {
			panic(err)
		}
		defer bf.Close()
		fileByName[backingFileName] = bf
	}

	totalSectors := volMeta.Size / volMeta.SectorSize

	location, names, err := sectormap.BuildSectorLocationMap(orderedChain, fileByName, backingFileName, totalSectors)
	if err != nil {
		panic(err)
	}

	fallbackName := volMeta.Head
	if backingFileName != "" {
		fallbackName = backingFileName
	}

	fmt.Println("--- raw extents per file ---")
	if err := sectormap.DumpExtents(orderedChain, fileByName, backingFileName, totalSectors); err != nil {
		panic(err)
	}

	fmt.Println("--- resolved sector ranges ---")
	sectormap.PrintSectorRanges(location, names, totalSectors, fallbackName)

	// Perform dry-run first to ensure the sectors about to be punched are as expected.
	fmt.Println("--- dry-run: punches that would be performed ---")
	if err := prune.PunchSnapshots(location, names, totalSectors, volMeta.SectorSize, diskMetas, true); err != nil {
		panic(err)
	}

	fmt.Print("\nProceed with actual punching? [y/N]: ")
	reader := bufio.NewReader(os.Stdin)
	answer, _ := reader.ReadString('\n')
	answer = strings.TrimSpace(strings.ToLower(answer))

	if answer != "y" && answer != "yes" {
		fmt.Println("Aborted, no changes made.")
		return
	}

	fmt.Println("--- punching obsolete ranges in ancestors ---")
	if err := prune.PunchSnapshots(location, names, totalSectors, volMeta.SectorSize, diskMetas, false); err != nil {
		panic(err)
	}
}
