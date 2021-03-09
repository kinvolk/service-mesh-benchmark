#!/bin/bash


function install_istio() {

    #Download Istio and switch to the folder
    curl -L https://istio.io/downloadIstio | sh -
    cd istio-1.9.1
    export PATH=$PWD/bin:$PATH

    #Install the demo profile
    echo "Istio is getting installed...."
    istioctl install --set profile=demo -y
    #Cleanup
    cd .. && rm -rf istio-1.9.1
}
# --

function install_consul() {

    #Add helm repo
    echo "Adding helm repo..."
    helm repo add hashicorp https://helm.releases.hashicorp.com

    #Install consul
    kubectl create ns consul && helm install -n consul -f consul-setup/consul-values.yaml consul hashicorp/consul  --version "0.27.0" --wait
    echo "Consul is getting installed...."
    if [ $? -eq 0 ]; then
        echo "Consul is installed onto the cluster"
    fi
}
# --

function install_linkerd() {

    #Check linkerd installation
    linkerd version
    if [ $? -ne 0 ]; then
        echo "linkerd cli is not installed on localhost. Installing the same...."
        curl -sL https://run.linkerd.io/install | sh
        export PATH=$PATH:$HOME/.linkerd2/bin
        brew install linkerd
    fi

    echo "linkerd cli is installed on localhost. Nothing to worry ......."
    #Install linkerd onto the cluster
    linkerd install | kubectl apply -f - > /dev/null 2>&1
    echo "linkerd is getting installed onto the cluster, let's check it....."
    linkerd check
    echo "linkerd installation onto the cluster is completed!!!!!"
}


function install_servicemeshes() {
    install_istio
    install_linkerd
    install_consul
}
# --

if [ "$(basename $0)" = "setup-servicemeshes.sh" ] ; then
    install_servicemeshes $@
fi
