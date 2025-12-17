resource "google_compute_network" "vpc" {
  name                    = "${var.project_name}-vpc"
  auto_create_subnetworks = false
  routing_mode            = "REGIONAL"
}

resource "google_compute_subnetwork" "subnet" {
  name          = "${var.project_name}-subnet"
  region        = var.region
  network       = google_compute_network.vpc.id
  ip_cidr_range = var.subnet_cidr
}

resource "google_compute_firewall" "allow_internal" {
  name    = "${var.project_name}-allow-internal"
  network = google_compute_network.vpc.name

  direction     = "INGRESS"
  source_ranges = [var.subnet_cidr]

  allow {
    protocol = "tcp"
    ports    = ["0-65535"]
  }
  allow {
    protocol = "udp"
    ports    = ["0-65535"]
  }
  allow {
    protocol = "icmp"
  }
}

resource "google_compute_firewall" "allow_iap_ssh" {
  count = var.enable_iap_ssh ? 1 : 0

  name    = "${var.project_name}-allow-iap-ssh"
  network = google_compute_network.vpc.name

  direction     = "INGRESS"
  source_ranges = ["35.235.240.0/20"] # Google IAP range
  target_tags   = ["iap-ssh"]

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
}

resource "google_compute_firewall" "allow_bastion_ssh" {
  name    = "${var.project_name}-allow-bastion-ssh"
  network = google_compute_network.vpc.name

  direction     = "INGRESS"
  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["bastion"]

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
}

# Allow Kubernetes API access through HAProxy on bastion
resource "google_compute_firewall" "allow_k8s_api" {
  name    = "${var.project_name}-allow-k8s-api"
  network = google_compute_network.vpc.name

  direction     = "INGRESS"
  source_ranges = ["0.0.0.0/0"] # TODO: Replace with IP whitelist
  target_tags   = ["bastion"]

  allow {
    protocol = "tcp"
    ports    = ["6443"]
  }
}

# Allow HTTP/HTTPS traffic through HAProxy on bastion (Ingress)
resource "google_compute_firewall" "allow_ingress_http" {
  name    = "${var.project_name}-allow-ingress-http"
  network = google_compute_network.vpc.name

  direction     = "INGRESS"
  source_ranges = ["0.0.0.0/0"] # TODO: Replace with IP whitelist
  target_tags   = ["bastion"]

  allow {
    protocol = "tcp"
    ports    = ["80", "443"]
  }
}

# Allow HAProxy stats access (optional, restrict in production)
resource "google_compute_firewall" "allow_haproxy_stats" {
  name    = "${var.project_name}-allow-haproxy-stats"
  network = google_compute_network.vpc.name

  direction     = "INGRESS"
  source_ranges = ["0.0.0.0/0"] # TODO: Replace with IP whitelist
  target_tags   = ["bastion"]

  allow {
    protocol = "tcp"
    ports    = ["8404"]
  }
}

resource "google_compute_router" "router" {
  count = var.enable_nat ? 1 : 0

  name    = "${var.project_name}-router"
  region  = var.region
  network = google_compute_network.vpc.id
}

resource "google_compute_router_nat" "nat" {
  count = var.enable_nat ? 1 : 0

  name                               = "${var.project_name}-nat"
  router                             = google_compute_router.router[0].name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
}
