package oci

import (
	"fmt"
	"log"
	"os"
	"strings"

	"github.com/kinvolk/service-mesh-benchmark/orchestrator/pkg/util"
)

func Deploy() {
	region := getRegion()
	fmt.Println("Region:", region)

	// Generate the Jobs list.
	var jobs []util.Job
	// Here we are trimming the last two chars from the region field since OCI has a small limit of
	// 15 chars so we can skip the `-1`s from the region names (me-dubai-1, ca-montreal-1) to give
	// enough room for the random number. OCI does not allow hypens in the DNS names so remove them.
	// Dots are allowed by OCI, but we cannot replace hypens with dots because they are not allowed
	// as terraform module name.
	name := util.GenerateName(region[3 : len(region)-2])
	name = strings.ReplaceAll(name, "-", "")[:15]

	jobs = append(jobs, util.Job{
		Name:   name,
		Region: region,
		Done:   false,
	})

	// Endless for loop that executes jobs, if those jobs fail then it creates new ones.
	util.ExecuteJobs(jobs)
}

func getRegion() string {
	region := os.Getenv("OCI_REGION")
	if region == "" {
		log.Fatal("OCI_REGION not set. Please provide the deployment region.")
	}

	return region
}
