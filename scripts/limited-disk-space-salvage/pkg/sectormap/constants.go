package sectormap

const (
	sectorSize = 512

	// maxExtentsPerCall bounds how many extents FIEMAP returns per ioctl call;
	// we page through with multiple calls if a file is more fragmented than this.
	maxExtentsPerCall = 1024
)
