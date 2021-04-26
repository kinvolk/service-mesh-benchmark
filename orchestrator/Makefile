build:
	go build

build-image: build
	docker build -t quay.io/kinvolk/smb-orchestrator .

push-image: build-image
	docker push quay.io/kinvolk/smb-orchestrator

build-image-dev: build
	docker build -t quay.io/kinvolk/smb-orchestrator:dev .

push-image-dev: build-image-dev
	docker push quay.io/kinvolk/smb-orchestrator:dev
