package main

import (
	"context"
	"fmt"
	"log"
	"os"
	"time"

	batchv1 "k8s.io/api/batch/v1"
	corev1 "k8s.io/api/core/v1"
	k8serrors "k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/client-go/kubernetes"
	"k8s.io/client-go/rest"
	"sigs.k8s.io/yaml"
)

// TODO: Create a configmap which is a way to know that the creation was complete and if this pod restarts it should not trigger the cluster creation.

type Job struct {
	Name   string
	Region string
	EIP    string
	Done   bool
}

var terraformCTVersion string

func main() {
	// Get the map of region name to its EIP.
	regionEIPs := getRegionEIPs()
	fmt.Println(regionEIPs)

	// Get the version of terraform_ct which will be passed on to the jobs.
	terraformCTVersion = os.Getenv("CT_VER")
	if terraformCTVersion == "" {
		log.Fatalf("CT_VER not set for terraform_ct version")
	}

	// Generate the Jobs list.
	var jobs []Job
	for facility, eip := range regionEIPs {
		jobs = append(jobs, Job{
			Name:   generateName(facility),
			Region: facility,
			EIP:    eip,
			Done:   false,
		})
	}

	// Endless for loop that executes jobs, if those jobs fail then it creates new ones.
	executeJobs(jobs)
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

// generateName generates cluster names. The format is
// 'bc-<region name>-<year><month><day><hour><minute><second>'
func generateName(region string) string {
	t := time.Now()
	return fmt.Sprintf("bc-%s-%d%d%d%d%d%d",
		region, t.Year(), t.Month(), t.Day(), t.Hour(), t.Minute(), t.Second())
}

// executeJobs generates a job per region and executes them. If a job fails then it is replaced by a
// new one. Makes sure all jobs exit to completion. Once all the jobs are done running it sleeps.
func executeJobs(jobs []Job) {
	config, err := rest.InClusterConfig()
	if err != nil {
		log.Fatalf("could not load in cluster kubeconfig: %v", err)
	}

	clientset, err := kubernetes.NewForConfig(config)
	if err != nil {
		log.Fatalf("could not create clientset: %v", err)
	}

	// Run this loop until all the jobs exit to completion.
	allDone := false
	for !allDone {
		// TODO: Remove this later
		log.Println("starting iteration over all jobs")

		for i, j := range jobs {
			// If a job is done no need to proceed.
			if j.Done {
				continue
			}

			// Get the job and if it does not exist then create it.
			jobObj, err := clientset.BatchV1().Jobs(namespace).Get(context.Background(), j.Name, metav1.GetOptions{})
			if err != nil {
				// Job not found create anew.
				if k8serrors.IsNotFound(err) {
					log.Printf("job: %q not found, creating...", j.Name)

					jobObj, err = clientset.BatchV1().Jobs(namespace).Create(context.Background(), getJob(j), metav1.CreateOptions{})
					if err != nil {
						log.Printf("error creating the job %q: %v", j.Name, err)
					}

					continue
				}

				// Some other error occurred when getting the job.
				log.Printf("error getting the job %q: %v", j.Name, err)
			}

			log.Printf("got job %q now looking for its 'status.conditions'", j.Name)

			// Now see if the job is marked as Complete or Failed
			// If it is Complete then mark it as Done in the Job object. If not replace it with new
			// one.
			// NOTE: By replace this only replaces the Job object in this applicaiton not the
			// Kubernetes Job.
			for _, c := range jobObj.Status.Conditions {
				switch c.Type {
				case batchv1.JobComplete:
					log.Printf("job: %q completed successfully", j.Name)
					jobs[i].Done = true
					continue
				case batchv1.JobFailed:
					log.Printf("job: %q failed, creating new one", j.Name)
					jobs[i] = Job{
						Name:   generateName(j.Region),
						Region: j.Region,
						EIP:    j.EIP,
						Done:   false,
					}
				}
			}
		}

		// Verify if any job is remaining. If even one job is remaining then keep iterating.
		allDone = true
		for _, j := range jobs {
			if !j.Done {
				allDone = false
				break
			}
		}

		// These jobs can take long time to finish, going on without sleeping will incur unnecessary
		// API calls to the kube-apiserver.
		time.Sleep(time.Minute * 2)
	}

	// Once done sleep forever, but keep emmiting this meesage.
	for allDone {
		log.Println("All jobs done! But don't kill this pod.")
		time.Sleep(time.Minute * 5)
	}
}

const (
	jobYaml = `
apiVersion: batch/v1
kind: Job
metadata:
  name: "placeholdername"
spec:
  template:
    spec:
      restartPolicy: Never
      containers:
      - image: surajd/jobrunner
        name: jobrunner
        envFrom:
        - secretRef:
            name: cloud-secrets
        command:
        - bash
        args:
        - -c
        - bash /scripts/run.sh
        volumeMounts:
        - name: binaries
          mountPath: /binaries
        - name: ssh-keys
          mountPath: /root/.ssh
          readOnly: true
        - name: cluster-assets
          mountPath: /clusters
        - name: cluster-install-configs
          mountPath: /scripts
      serviceAccountName: jobrunner
      volumes:
      - name: binaries
        persistentVolumeClaim:
          claimName: binaries
      - name: cluster-assets
        persistentVolumeClaim:
          claimName: bc-assets
      - name: ssh-keys
        secret:
          defaultMode: 256
          secretName: ssh-keys
      - name: cluster-install-configs
        configMap:
          name: cluster-install-configs
`
	namespace = "orchestrator"
)

// getJob parses the above Kubernetes Job config and then creates a Job object out of it.
// But apart from parsing it also sets some values that are necessary for a Job to create cluster
// correctly.
func getJob(j Job) *batchv1.Job {
	var ret batchv1.Job
	if err := yaml.Unmarshal([]byte(jobYaml), &ret); err != nil {
		panic(fmt.Sprintf("problematic job yaml: %v", err))
	}

	ret.Name = j.Name
	ret.Spec.Template.Spec.Containers[0].Env = []corev1.EnvVar{
		{Name: "CT_VER", Value: terraformCTVersion},
		{Name: "PACKET_REGION", Value: j.Region},
		{Name: "PUBLIC_EIP", Value: j.EIP},
		{Name: "CLUSTER_NAME", Value: j.Name},
	}

	return &ret
}
