#!/bin/bash

read -p "Please enter your Google Cloud Project ID: " USER_PROJECT_ID

if [ -z "$USER_PROJECT_ID" ]; then
    echo "Error: Project ID cannot be empty. Exiting."
    exit 1
fi

echo "Using Project ID: $USER_PROJECT_ID"


# Region & Zone 
REGION="europe-west3"
ZONE="europe-west3-a"


SCHEDULE_NAME="stop-k8s-cluster-nightly"
TIMEZONE="Europe/Istanbul"

# Cron: 22:00 (10 PM) Daily
STOP_CRON="0 22 * * *"

# List of Instances 
TARGET_INSTANCES=(
    "bastion"
    "master-01"
    "master-02"
    "master-03"
    "worker-01"
    "worker-02"
)



echo "Starting schedule setup for Region: $REGION..."

#Resource Policy
echo "Creating resource policy: $SCHEDULE_NAME..."
gcloud compute resource-policies create instance-schedule $SCHEDULE_NAME \
    --project=$USER_PROJECT_ID \
    --region=$REGION \
    --vm-stop-schedule="$STOP_CRON" \
    --timezone=$TIMEZONE \
    --description="Stops Kubernetes cluster at 22:00 TRT to save costs." \
    || echo "Policy might already exist. Proceeding..."

echo "Attaching policy to instances..."

for INSTANCE in "${TARGET_INSTANCES[@]}"
do
    echo "Processing instance: $INSTANCE..."
    
    gcloud compute instances add-resource-policies $INSTANCE \
        --project=$USER_PROJECT_ID \
        --zone=$ZONE \
        --resource-policies=$SCHEDULE_NAME \
        --quiet
        
    if [ $? -eq 0 ]; then
        echo "Successfully attached schedule to $INSTANCE."
    else
        echo "Failed to attach to $INSTANCE (or already attached)."
    fi
done
