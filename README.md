# Fuck Google

## login gcloud

```bash
gcloud iam service-accounts create tf-lab --display-name="Terraform lab SA"
```

```bash
gcloud projects add-iam-policy-binding $YOUR_PROJECT_ID \
  --member="serviceAccount:tf-lab@$YOUR_PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/editor"
```

```bash
gcloud iam service-accounts keys create ./tf-lab-sa.json \
  --iam-account="tf-lab@$YOUR_PROJECT_ID.iam.gserviceaccount.com"
```

```bash
export GOOGLE_IMPERSONATE_SERVICE_ACCOUNT="tf-sa@$YOUR_PROJECT_ID.iam.gserviceaccount.com"
```

## Terraform Output

```bash
terraform output -json all_nodes > ../artifacts/nodes.json
```

## Tools

### gen-inventory

```bash
python3 tools/generate-hosts.py -i artifacts/nodes.json -o ansible/kubespray/inventory/inventory.ini --ansible-user debian --become
```
