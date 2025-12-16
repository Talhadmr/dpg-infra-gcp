.PHONY: help init plan apply destroy inventory setup-ssh ssh-bastion ssh-master ping deploy reset clean setup-kubespray kubeconfig setup-gcp haproxy renew-certs

ZONE ?= europe-west3-a
KUBESPRAY_VERSION ?= v2.25.0
VENV ?= .venv
ANSIBLE_USER ?= $(shell gcloud compute os-login describe-profile --format="value(posixAccounts[0].username)" 2>/dev/null || echo "debian")

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

all: init apply inventory setup-ssh

kubeconfig:
	@BASTION_IP=$$(terraform -chdir=./terraform output -raw bastion_public_ip 2>/dev/null); \
	MASTER_IP=$$(terraform -chdir=./terraform output -json master_nodes 2>/dev/null | jq -r '."master-01".ip'); \
	ssh -o StrictHostKeyChecking=no -J $(ANSIBLE_USER)@$$BASTION_IP $(ANSIBLE_USER)@$$MASTER_IP \
		"sudo cat /etc/kubernetes/admin.conf" > artifacts/kubeconfig; \
	BASTION_IP=$$(terraform -chdir=./terraform output -raw bastion_public_ip 2>/dev/null); \
	sed -i '' "s|server: https://[0-9.]*:6443|server: https://$$BASTION_IP:6443|" artifacts/kubeconfig; \
	echo "Kubeconfig saved: artifacts/kubeconfig (API: https://$$BASTION_IP:6443)"

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

clean:
	rm -f artifacts/nodes.json
	rm -f artifacts/kubeconfig
	rm -f ansible/inventory/inventory.ini
	rm -rf ansible/inventory/group_vars/
