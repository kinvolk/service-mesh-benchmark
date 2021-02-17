package equinixmetal

import (
	"fmt"
	"log"
	"os"

	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"

	"github.com/kinvolk/service-mesh-benchmark/orchestrator/pkg/util"
)

func Deploy() {
	// Get the map of region name to its EIP.
	regionEIPs := getRegionEIPs()
	fmt.Println("Facility - EIP mapping:", regionEIPs)

	// Generate the Jobs list.
	var jobs []util.Job
	for facility, eip := range regionEIPs {
		jobs = append(jobs, util.Job{
			Name:   util.GenerateName(facility),
			Region: facility,
			EIP:    eip,
			Done:   false,
		})
	}

	// Endless for loop that executes jobs, if those jobs fail then it creates new ones.
	util.ExecuteJobs(jobs)
}

func getRegionEIPs() map[string]string {
	eipsStr := os.Getenv("REGION_EIPS")
	if eipsStr == "" {
		log.Fatal("REGION_EIPS not set. Please provide a comma separated list of region=eip.")
	}

	// Now these jobs will be provided in the same format as label selector for kubectl.
	// For e.g. k1=v1,k2=v2
	ls, err := metav1.ParseToLabelSelector(eipsStr)
	if err != nil {
		log.Fatalf("Could not parse the REGION_EIPS: %v", err)
	}

	// This converts the k1=v1,k2=v2 to map[string]string
	// {k1:v1, k2:v2}
	ret, err := metav1.LabelSelectorAsMap(ls)
	if err != nil {
		log.Fatalf("Could not convert the REGION_EIPS: %v", err)
	}

	// Make sure that the EIPs provided have /32 in the end.
	// Using above API for converting comma separated key value pair to map don't support having
	// slash / in it. So this program does not expect user to provide /32 either. So since user
	// isn't providing it we have to add it manually here.
	for k, v := range ret {
		v += "/32"
		ret[k] = v
	}

	return ret
}
