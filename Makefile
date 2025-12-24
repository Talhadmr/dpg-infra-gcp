.PHONY: help init plan apply destroy inventory setup-ssh ssh-bastion ssh-master ping deploy reset clean setup-kubespray kubeconfig setup-gcp haproxy renew-certs namespaces argocd bootstrap gitops helm-deps

ZONE ?= europe-west3-a
KUBESPRAY_VERSION ?= v2.25.0
VENV ?= .venv
ANSIBLE_USER ?= $(shell gcloud compute os-login describe-profile --format="value(posixAccounts[0].username)" 2>/dev/null || echo "debian")

# GitOps Configuration
GIT_REPO_URL ?= https://github.com/Talhadmr/dpg-infra-gcp.git
GIT_TARGET_REVISION ?= HEAD


init:
	terraform -chdir=./terraform init

plan:
	terraform -chdir=./terraform plan

apply:
	terraform -chdir=./terraform apply

destroy:
	terraform -chdir=./terraform destroy


inventory:
	terraform -chdir=./terraform refresh
	terraform -chdir=./terraform output -json all_nodes > artifacts/nodes.json
	python3 tools/generate-hosts.py \
		--input artifacts/nodes.json \
		--output ansible/inventory/inventory.ini \
		--ansible-user $(ANSIBLE_USER) \
		--become

setup-ssh:
	@BASTION_IP=$$(terraform -chdir=./terraform output -raw bastion_public_ip 2>/dev/null); \
	if [ -z "$$BASTION_IP" ] || [ "$$BASTION_IP" = "null" ]; then \
		echo "ERROR: Bastion has no public IP. Run 'make apply' first."; \
		exit 1; \
	fi; \
	echo "Bastion IP: $$BASTION_IP"; \
	echo "Testing SSH connection..."; \
	ssh -o StrictHostKeyChecking=no $(ANSIBLE_USER)@$$BASTION_IP "echo 'Bastion OK!'"

ssh-bastion:
	@BASTION_IP=$$(terraform -chdir=./terraform output -raw bastion_public_ip 2>/dev/null); \
	if [ -n "$$BASTION_IP" ] && [ "$$BASTION_IP" != "null" ]; then \
		ssh $(ANSIBLE_USER)@$$BASTION_IP; \
	else \
		gcloud compute ssh bastion --zone=$(ZONE) --tunnel-through-iap; \
	fi

ssh-master:
	@BASTION_IP=$$(terraform -chdir=./terraform output -raw bastion_public_ip 2>/dev/null); \
	MASTER_IP=$$(terraform -chdir=./terraform output -json master_nodes 2>/dev/null | jq -r '."master-01".ip'); \
	if [ -n "$$BASTION_IP" ] && [ "$$BASTION_IP" != "null" ]; then \
		ssh -J $(ANSIBLE_USER)@$$BASTION_IP $(ANSIBLE_USER)@$$MASTER_IP; \
	else \
		gcloud compute ssh master-01 --zone=$(ZONE) --tunnel-through-iap; \
	fi

setup-gcp:
	@SSH_KEY=""; \
	for key in $$HOME/.ssh/id_ed25519.pub $$HOME/.ssh/id_rsa.pub $$HOME/.ssh/id_ecdsa.pub; do \
		if [ -f "$$key" ]; then SSH_KEY="$$key"; break; fi; \
	done; \
	if [ -z "$$SSH_KEY" ]; then \
		echo "ERROR: No SSH public key found in ~/.ssh/"; \
		exit 1; \
	fi; \
	echo "Found SSH key: $$SSH_KEY"; \
	gcloud compute os-login ssh-keys add --key-file="$$SSH_KEY"; \
	echo ""; \
	echo "Adding IAM role..."; \
	gcloud projects add-iam-policy-binding $$(gcloud config get-value project) \
		--member="user:$$(gcloud config get-value account)" \
		--role="roles/compute.osAdminLogin" --quiet; \
	echo ""; \
	echo "Done! Your OS Login username: $$(gcloud compute os-login describe-profile --format='value(posixAccounts[0].username)')"

ping:
	@if [ -d "$(VENV)" ]; then \
		cd ansible && ../$(VENV)/bin/ansible -i inventory/inventory.ini all -m ping; \
	else \
		cd ansible && ansible -i inventory/inventory.ini all -m ping; \
	fi


setup-kubespray:
	@if [ ! -d "ansible/kubespray" ]; then \
		git clone --branch $(KUBESPRAY_VERSION) --depth 1 \
			https://github.com/kubernetes-sigs/kubespray.git ansible/kubespray; \
	fi
	python3 -m venv $(VENV)
	$(VENV)/bin/pip install --upgrade pip
	$(VENV)/bin/pip install -r ansible/kubespray/requirements.txt
	$(VENV)/bin/pip install kubernetes  # Required for kubernetes.core module
	$(VENV)/bin/ansible-galaxy collection install kubernetes.core

deploy: inventory
	cd ansible/kubespray && ../../$(VENV)/bin/ansible-playbook -i ../inventory/inventory.ini \
		cluster.yml \
		--become --become-user=root \
		-v

reset:
	@read -p "Reset cluster? [y/N] " confirm && [ "$$confirm" = "y" ] || exit 1
	cd ansible/kubespray && ../../$(VENV)/bin/ansible-playbook -i ../inventory/inventory.ini \
		reset.yml \
		--become --become-user=root \
		-v

kubeconfig:
	@BASTION_IP=$$(terraform -chdir=./terraform output -raw bastion_public_ip 2>/dev/null); \
	MASTER_IP=$$(terraform -chdir=./terraform output -json master_nodes 2>/dev/null | jq -r '."master-01".ip'); \
	ssh -o StrictHostKeyChecking=no -J $(ANSIBLE_USER)@$$BASTION_IP $(ANSIBLE_USER)@$$MASTER_IP \
		"sudo cat /etc/kubernetes/admin.conf" > artifacts/kubeconfig; \
	BASTION_IP=$$(terraform -chdir=./terraform output -raw bastion_public_ip 2>/dev/null); \
	sed -i '' "s|server: https://[0-9.]*:6443|server: https://$$BASTION_IP:6443|" artifacts/kubeconfig; \
	echo "Kubeconfig saved: artifacts/kubeconfig (API: https://$$BASTION_IP:6443)"; \
	echo ""; \
	echo "To use: export KUBECONFIG=$$(pwd)/artifacts/kubeconfig"


haproxy:
	@if [ -d "$(VENV)" ]; then \
		$(VENV)/bin/ansible-playbook -i ansible/inventory/inventory.ini \
			ansible/haproxy/playbook.yml \
			--become --become-user=root \
			-v; \
	else \
		ansible-playbook -i ansible/inventory/inventory.ini \
			ansible/haproxy/playbook.yml \
			--become --become-user=root \
			-v; \
	fi

renew-certs: inventory
	@BASTION_IP=$$(terraform -chdir=./terraform output -raw bastion_public_ip 2>/dev/null); \
	echo "==> Bastion IP: $$BASTION_IP"; \
	echo "==> Regenerating API server certificates with new SAN..."; \
	cd ansible && ../$(VENV)/bin/ansible -i inventory/inventory.ini kube_control_plane \
		--become --become-user=root \
		-m shell -a " \
			rm -f /etc/kubernetes/pki/apiserver.* 2>/dev/null || true; \
			kubeadm init phase certs apiserver --apiserver-cert-extra-sans=$$BASTION_IP; \
			systemctl restart kubelet; \
			sleep 5; \
			crictl ps | grep kube-apiserver | awk '{print \$$1}' | xargs -r crictl stop; \
		"; \
	echo ""; \
	echo "==> Done! Waiting for API server to restart..."; \
	sleep 10

namespaces:
	@echo "==> Creating Kubernetes namespaces..."
	@if [ -d "$(VENV)" ]; then \
		KUBECONFIG=$$(pwd)/artifacts/kubeconfig $(VENV)/bin/ansible-playbook \
			ansible/cluster/playbook.yml -v; \
	else \
		KUBECONFIG=$$(pwd)/artifacts/kubeconfig ansible-playbook \
			ansible/cluster/playbook.yml -v; \
	fi

argocd:
	@echo "==> Installing ArgoCD via Helm..."
	@if [ -d "$(VENV)" ]; then \
		KUBECONFIG=$$(pwd)/artifacts/kubeconfig $(VENV)/bin/ansible-playbook \
			ansible/argocd/install.yml -v; \
	else \
		KUBECONFIG=$$(pwd)/artifacts/kubeconfig ansible-playbook \
			ansible/argocd/install.yml -v; \
	fi

bootstrap:
	@echo "==> Applying Bootstrap Application to ArgoCD..."
	@if [ -d "$(VENV)" ]; then \
		KUBECONFIG=$$(pwd)/artifacts/kubeconfig \
		GIT_REPO_URL=$(GIT_REPO_URL) \
		GIT_TARGET_REVISION=$(GIT_TARGET_REVISION) \
		$(VENV)/bin/ansible-playbook ansible/argocd/bootstrap.yml -v; \
	else \
		KUBECONFIG=$$(pwd)/artifacts/kubeconfig \
		GIT_REPO_URL=$(GIT_REPO_URL) \
		GIT_TARGET_REVISION=$(GIT_TARGET_REVISION) \
		ansible-playbook ansible/argocd/bootstrap.yml -v; \
	fi

helm-deps:
	find workloads -name Chart.yaml -execdir helm dependency build \; 


gitops: haproxy namespaces argocd helm-deps bootstrap
	@echo ""
	@echo "============================================"
	@echo "GitOps Setup Complete!"
	@echo "============================================"
	@echo ""
	@echo "ArgoCD UI access:"
	@echo "  kubectl port-forward svc/argocd-server -n argocd 8080:443"
	@echo "  Then open: https://localhost:8080"
	@echo ""
	@echo "Get admin password:"
	@echo "  kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
	@echo ""
	@echo "Monitor applications:"
	@echo "  kubectl get applications -n argocd"
	@echo ""

all: init apply inventory setup-ssh

# Full cluster setup: Infrastructure + K8s + GitOps
full-setup: apply inventory setup-ssh deploy kubeconfig renew-certs gitops

clean:
	rm -f artifacts/nodes.json
	rm -f artifacts/kubeconfig
	rm -f ansible/inventory/inventory.ini
	rm -rf ansible/inventory/group_vars/


help:
	@echo "DPG Infrastructure - Available Commands"
	@echo "========================================"
	@echo ""
	@echo "Infrastructure:"
	@echo "  make init          - Initialize Terraform"
	@echo "  make plan          - Show Terraform plan"
	@echo "  make apply         - Apply Terraform configuration"
	@echo "  make destroy       - Destroy all resources"
	@echo ""
	@echo "Inventory & SSH:"
	@echo "  make inventory     - Generate Ansible inventory"
	@echo "  make setup-gcp     - Configure OS Login SSH key"
	@echo "  make setup-ssh     - Test SSH to bastion"
	@echo "  make ssh-bastion   - SSH into bastion host"
	@echo "  make ssh-master    - SSH into master-01"
	@echo "  make ping          - Ansible ping all nodes"
	@echo ""
	@echo "Kubernetes:"
	@echo "  make setup-kubespray - Clone Kubespray + setup venv"
	@echo "  make deploy        - Deploy K8s cluster"
	@echo "  make reset         - Reset K8s cluster"
	@echo "  make kubeconfig    - Fetch kubeconfig"
	@echo ""
	@echo "Edge Router (HAProxy):"
	@echo "  make haproxy       - Install/update HAProxy"
	@echo "  make renew-certs   - Regenerate API server certs"
	@echo ""
	@echo "GitOps (ArgoCD):"
	@echo "  make namespaces    - Create K8s namespaces"
	@echo "  make argocd        - Install ArgoCD"
	@echo "  make bootstrap     - Apply App of Apps"
	@echo "  make gitops        - Full GitOps setup"
	@echo "  make helm-deps     - Update Helm dependencies"
	@echo ""
	@echo "Combined:"
	@echo "  make all           - Infrastructure + inventory + SSH"
	@echo "  make full-setup    - Complete cluster + GitOps setup"
	@echo "  make clean         - Remove generated files"
