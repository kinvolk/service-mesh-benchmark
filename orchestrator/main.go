package main

import (
	"log"
	"os"

	"github.com/kinvolk/service-mesh-benchmark/orchestrator/pkg/equinixmetal"
)

// TODO: Create a configmap which is a way to know that the creation was complete and if this pod
// restarts it should not trigger the cluster creation.

func main() {
	bcCloud := os.Getenv("BENCHMARKING_CLUSTER_CLOUD")

	switch bcCloud {
	case "equinix-metal":
		equinixmetal.Deploy()
	default:
		log.Fatalf("Given cloud provider not supported: %q.", bcCloud)
	}
}
