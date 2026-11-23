locals {
  project_tags = {
    Project     = "norcom-cloud-academic"
    Environment = "mail-lab"
    ManagedBy   = "Terraform"
  }
  setup_ports  = { ssh = 22, https = 443 }
  public_ports = var.enable_public_mail ? { smtp = 25, http = 80, https = 443 } : {}
  client_ports = var.enable_mail_clients ? { submission = 587, imaps = 993 } : {}
}

data "oci_core_images" "ubuntu_arm" {
  compartment_id           = var.compartment_ocid
  operating_system         = "Canonical Ubuntu"
  operating_system_version = "24.04"
  shape                    = "VM.Standard.A1.Flex"
  state                    = "AVAILABLE"
  sort_by                  = "TIMECREATED"
  sort_order               = "DESC"
}

resource "oci_core_vcn" "mail" {
  compartment_id = var.compartment_ocid
  cidr_blocks    = ["10.53.0.0/24"]
  display_name   = "norcom-mail-lab-vcn"
  dns_label      = "norcommail"
  freeform_tags  = local.project_tags
}

resource "oci_core_internet_gateway" "mail" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.mail.id
  display_name   = "norcom-mail-lab-igw"
  enabled        = true
  freeform_tags  = local.project_tags
}

resource "oci_core_route_table" "mail" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.mail.id
  display_name   = "norcom-mail-lab-routes"
  freeform_tags  = local.project_tags

  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_internet_gateway.mail.id
  }
}

resource "oci_core_security_list" "mail" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.mail.id
  display_name   = "norcom-mail-lab-firewall"
  freeform_tags  = local.project_tags

  egress_security_rules {
    destination      = "0.0.0.0/0"
    destination_type = "CIDR_BLOCK"
    protocol         = "all"
  }

  dynamic "ingress_security_rules" {
    for_each = local.setup_ports
    content {
      protocol    = "6"
      source      = var.admin_cidr
      source_type = "CIDR_BLOCK"
      tcp_options {
        min = ingress_security_rules.value
        max = ingress_security_rules.value
      }
    }
  }

  dynamic "ingress_security_rules" {
    for_each = merge(local.public_ports, local.client_ports)
    content {
      protocol    = "6"
      source      = "0.0.0.0/0"
      source_type = "CIDR_BLOCK"
      tcp_options {
        min = ingress_security_rules.value
        max = ingress_security_rules.value
      }
    }
  }
}

resource "oci_core_subnet" "mail" {
  compartment_id             = var.compartment_ocid
  vcn_id                     = oci_core_vcn.mail.id
  cidr_block                 = "10.53.0.0/24"
  display_name               = "norcom-mail-lab-public"
  dns_label                  = "public"
  prohibit_public_ip_on_vnic = false
  route_table_id             = oci_core_route_table.mail.id
  security_list_ids          = [oci_core_security_list.mail.id]
  freeform_tags              = local.project_tags
}

resource "oci_core_instance" "mail" {
  compartment_id      = var.compartment_ocid
  availability_domain = var.availability_domain
  fault_domain        = var.fault_domain
  display_name        = "norcom-mailcow-lab"
  shape               = "VM.Standard.A1.Flex"
  freeform_tags       = local.project_tags

  shape_config {
    ocpus         = var.ocpus
    memory_in_gbs = var.memory_in_gbs
  }

  create_vnic_details {
    subnet_id        = oci_core_subnet.mail.id
    assign_public_ip = true
    hostname_label   = "mailcow"
  }

  source_details {
    source_type             = "image"
    source_id               = data.oci_core_images.ubuntu_arm.images[0].id
    boot_volume_size_in_gbs = 50
  }

  metadata = {
    ssh_authorized_keys = var.ssh_public_key
  }

  lifecycle {
    precondition {
      condition     = length(data.oci_core_images.ubuntu_arm.images) > 0
      error_message = "No hay imagen Ubuntu 24.04 compatible con A1 en Vinhedo."
    }
  }
}
