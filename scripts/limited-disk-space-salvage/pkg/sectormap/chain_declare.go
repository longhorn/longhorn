package sectormap

import (
	"fmt"
	"os"
)

type LayerFileMap map[string]*os.File

func OpenLayers(chain []string, flag int) (LayerFileMap, error) {
	files := make(LayerFileMap, len(chain))
	for _, name := range chain {
		file, err := os.OpenFile(name, flag, 0)
		if err != nil {
			files.Close()
			return nil, fmt.Errorf("failed to open %s: %w", name, err)
		}
		//layers = append(layers, Layer{Name: name, File: f})
		files[name] = file
	}
	return files, nil
}

func (m LayerFileMap) Close() {
	for _, l := range m {
		_ = l.Close()
	}
}

func (m LayerFileMap) Get(name string) (*os.File, error) {
	f, ok := m[name]
	if !ok {
		return nil, fmt.Errorf("no open file for %s", name)
	}
	return f, nil
}
