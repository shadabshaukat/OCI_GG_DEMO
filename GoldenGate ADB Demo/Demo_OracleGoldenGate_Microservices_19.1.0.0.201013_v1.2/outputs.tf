// Copyright (c) 2019, Oracle and/or its affiliates. All rights reserved.

output "ogg_instance_id" {
  value = "${module.ogg_compute.instance_id}"
}

output "ogg_image_id" {
  value = "${module.ogg_compute.image_id}"
}

output "ogg_public_ip" {
  value = "${module.ogg_compute.public_ip}"
}
