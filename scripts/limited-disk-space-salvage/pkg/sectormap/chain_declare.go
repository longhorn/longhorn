package sectormap

import (
	"fmt"
	"os"
)

type LayerFileMap map[string]*os.File

// OpenLayers opens each file in chain with the given flag and returns a
// LayerFileMap map[name]open_*os.File. On error it closes any files
// already opened before returning.
func OpenLayers(chain []string, flag int) (LayerFileMap, error) {
	files := make(LayerFileMap, len(chain))
	for _, name := range chain {
		file, err := os.OpenFile(name, flag, 0)
		if err != nil {
			files.Close()
			return nil, fmt.Errorf("failed to open %s: %w", name, err)
		}
		files[name] = file
	}
	return files, nil
}

// Close closes all open files in the map.
func (m LayerFileMap) Close() {
	for _, l := range m {
		_ = l.Close()
	}
}

// Get returns the open file for name, or an error if it isn't in the map.
func (m LayerFileMap) Get(name string) (*os.File, error) {
	f, ok := m[name]
	if !ok {
		return nil, fmt.Errorf("no open file for %s", name)
	}
	return f, nil
}
