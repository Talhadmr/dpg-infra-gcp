.PHONY: help init plan apply destroy inventory setup-ssh ssh-bastion ssh-master ping deploy reset clean setup-kubespray kubeconfig kubectl

# Configuration
ZONE ?= europe-west3-a
ANSIBLE_USER ?= talha_demir_mail_gmail_com
KUBESPRAY_VERSION ?= v2.25.0
SSH_KEY ?= ~/.ssh/id_ed25519
VENV ?= .venv


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
	@mkdir -p kubeconfig
	@BASTION_IP=$$(terraform -chdir=./terraform output -raw bastion_public_ip 2>/dev/null); \
	MASTER_IP=$$(terraform -chdir=./terraform output -json master_nodes 2>/dev/null | jq -r '."master-01".ip'); \
	ssh -o StrictHostKeyChecking=no -J $(ANSIBLE_USER)@$$BASTION_IP $(ANSIBLE_USER)@$$MASTER_IP \
		"sudo cat /etc/kubernetes/admin.conf" > kubeconfig/config; \
	echo "Kubeconfig saved: kubeconfig/config"

kubectl:
	@BASTION_IP=$$(terraform -chdir=./terraform output -raw bastion_public_ip 2>/dev/null); \
	MASTER_IP=$$(terraform -chdir=./terraform output -json master_nodes 2>/dev/null | jq -r '."master-01".ip'); \
	echo "Opening SSH tunnel: localhost:6443 -> $$MASTER_IP:6443"; \
	ssh -o StrictHostKeyChecking=no -N -L 6443:$$MASTER_IP:6443 -J $(ANSIBLE_USER)@$$BASTION_IP $(ANSIBLE_USER)@$$MASTER_IP

clean:
	rm -f artifacts/nodes.json
	rm -f ansible/inventory/inventory.ini
	rm -rf kubeconfig/
