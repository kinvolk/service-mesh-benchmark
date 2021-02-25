package aws

import (
	"fmt"
	"log"
	"os"
	"strings"

	"github.com/kinvolk/service-mesh-benchmark/orchestrator/pkg/util"
)

func Deploy() {
	// Get the map of region name to its EIP.
	regions := getRegions()
	fmt.Println("Regions:", regions)

	// Generate the Jobs list.
	var jobs []util.Job
	for _, region := range regions {
		jobs = append(jobs, util.Job{
			Name:   util.GenerateName(region),
			Region: region,
			Done:   false,
		})
	}

	// Endless for loop that executes jobs, if those jobs fail then it creates new ones.
	util.ExecuteJobs(jobs)
}

func getRegions() []string {
	regions := os.Getenv("AWS_REGIONS")
	if regions == "" {
		log.Fatal("AWS_REGIONS not set. Please provide a comma separated list of region.")
	}

	return strings.Split(regions, ",")
}
