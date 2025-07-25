# main.tf - N8N Infrastructure with DigitalOcean Spaces State Backend

terraform {
  backend "s3" {
    # DigitalOcean Spaces configuration
    endpoint                    = "https://sfo3.digitaloceanspaces.com"
    bucket                     = "truji"
    key                        = "n8n-infrastructure/terraform.tfstate"
    region                     = "us-east-1"  # Required but ignored by DO Spaces
    
    # DigitalOcean Spaces specific settings
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    force_path_style           = false
  }
  
  required_providers {
    digitalocean = {
      source  = "digitalocean/digitalocean"
      version = "~> 2.0"
    }
  }
}

# Configure the DigitalOcean Provider
provider "digitalocean" {
  token = var.do_token
}

# Variables
variable "do_token" {
  description = "DigitalOcean API Token"
  type        = string
  sensitive   = true
}

variable "ssh_public_key" {
  description = "SSH public key content"
  type        = string
}

variable "domain_name" {
  description = "Domain name for n8n (e.g., n8n.truji.dev)"
  type        = string
  default     = ""
}

variable "postgres_password" {
  description = "PostgreSQL password"
  type        = string
  sensitive   = true
  default     = "n8n_secure_password_123"
}

variable "n8n_basic_auth_user" {
  description = "N8N basic auth username"
  type        = string
  default     = "admin"
}

variable "n8n_basic_auth_password" {
  description = "N8N basic auth password"
  type        = string
  sensitive   = true
  default     = "n8n_admin_password_123"
}

variable "droplet_size" {
  description = "DigitalOcean droplet size"
  type        = string
  default     = "s-1vcpu-1gb"
}

variable "region" {
  description = "DigitalOcean region"
  type        = string
  default     = "sfo3"
}

# SSH Key
resource "digitalocean_ssh_key" "n8n_key" {
  name       = "n8n-server-key"
  public_key = var.ssh_public_key
}

# Create DNS zone in DigitalOcean
resource "digitalocean_domain" "truji_dev" {
  name = "truji.dev"
}

# Droplet
resource "digitalocean_droplet" "n8n_server" {
  image    = "ubuntu-24-04-x64"
  name     = "n8n-server"
  region   = var.region
  size     = var.droplet_size
  ssh_keys = [digitalocean_ssh_key.n8n_key.fingerprint]

  user_data = templatefile("${path.module}/cloud-init.yml", {
    postgres_password       = var.postgres_password
    n8n_basic_auth_user    = var.n8n_basic_auth_user
    n8n_basic_auth_password = var.n8n_basic_auth_password
    domain_name            = var.domain_name
    ssh_public_key         = var.ssh_public_key
  })

  tags = ["n8n", "automation", "terraform"]

  lifecycle {
    prevent_destroy = false
  }
}

# A record for N8N subdomain
resource "digitalocean_record" "n8n" {
  domain = digitalocean_domain.truji_dev.name
  type   = "A"
  name   = "n8n"
  value  = digitalocean_droplet.n8n_server.ipv4_address
  ttl    = 300
}

# Optional: Root domain A record (points to same server)
resource "digitalocean_record" "root" {
  domain = digitalocean_domain.truji_dev.name
  type   = "A"
  name   = "@"
  value  = digitalocean_droplet.n8n_server.ipv4_address
  ttl    = 300
}

# Optional: WWW subdomain (CNAME to root)
resource "digitalocean_record" "www" {
  domain = digitalocean_domain.truji_dev.name
  type   = "CNAME"
  name   = "www"
  value  = "truji.dev."
  ttl    = 300
}

# Firewall
resource "digitalocean_firewall" "n8n_firewall" {
  name = "n8n-firewall"

  droplet_ids = [digitalocean_droplet.n8n_server.id]

  # SSH
  inbound_rule {
    protocol         = "tcp"
    port_range       = "22"
    source_addresses = ["0.0.0.0/0", "::/0"]
  }

  # HTTP
  inbound_rule {
    protocol         = "tcp"
    port_range       = "80"
    source_addresses = ["0.0.0.0/0", "::/0"]
  }

  # HTTPS
  inbound_rule {
    protocol         = "tcp"
    port_range       = "443"
    source_addresses = ["0.0.0.0/0", "::/0"]
  }

  # All outbound traffic
  outbound_rule {
    protocol              = "tcp"
    port_range            = "1-65535"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }

  outbound_rule {
    protocol              = "udp"
    port_range            = "1-65535"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }

  outbound_rule {
    protocol              = "icmp"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }
}

# Outputs
output "server_ip" {
  description = "Public IP address of the n8n server"
  value       = digitalocean_droplet.n8n_server.ipv4_address
}

output "server_url" {
  description = "URL to access n8n"
  value       = var.domain_name != "" ? "https://${var.domain_name}" : "http://${digitalocean_droplet.n8n_server.ipv4_address}"
}

output "ssh_command" {
  description = "SSH command to connect to the server"
  value       = "ssh n8nuser@${var.domain_name != "" ? var.domain_name : digitalocean_droplet.n8n_server.ipv4_address}"
}

output "basic_auth_credentials" {
  description = "N8N basic auth credentials"
  value = {
    username = var.n8n_basic_auth_user
    password = var.n8n_basic_auth_password
  }
  sensitive = true
}

output "dns_instructions" {
  description = "DNS setup instructions"
  value = "Update nameservers at Namecheap to use DigitalOcean DNS"
}

output "digitalocean_nameservers" {
  description = "DigitalOcean nameservers to configure at Namecheap"
  value = [
    "ns1.digitalocean.com",
    "ns2.digitalocean.com", 
    "ns3.digitalocean.com"
  ]
}

output "dns_records_created" {
  description = "DNS records created in DigitalOcean"
  value = {
    n8n_subdomain = digitalocean_record.n8n.fqdn
    root_domain   = digitalocean_record.root.fqdn
    www_subdomain = digitalocean_record.www.fqdn
  }
}