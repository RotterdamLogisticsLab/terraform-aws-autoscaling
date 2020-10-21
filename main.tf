#######################
# Launch configuration
#######################
resource "aws_launch_configuration" "this" {
  count = var.create_lc ? 1 : 0

  name_prefix                 = "${coalesce(var.lc_name, var.name)}-"
  image_id                    = var.image_id
  instance_type               = var.instance_type
  iam_instance_profile        = var.iam_instance_profile
  key_name                    = var.key_name
  security_groups             = var.security_groups
  associate_public_ip_address = var.associate_public_ip_address
  user_data                   = var.user_data
  user_data_base64            = var.user_data_base64
  enable_monitoring           = var.enable_monitoring
  spot_price                  = var.spot_price
  placement_tenancy           = var.spot_price == "" ? var.placement_tenancy : ""
  ebs_optimized               = var.ebs_optimized

  dynamic "ebs_block_device" {
    for_each = var.ebs_block_device
    content {
      delete_on_termination = lookup(ebs_block_device.value, "delete_on_termination", null)
      device_name           = ebs_block_device.value.device_name
      encrypted             = lookup(ebs_block_device.value, "encrypted", null)
      iops                  = lookup(ebs_block_device.value, "iops", null)
      no_device             = lookup(ebs_block_device.value, "no_device", null)
      snapshot_id           = lookup(ebs_block_device.value, "snapshot_id", null)
      volume_size           = lookup(ebs_block_device.value, "volume_size", null)
      volume_type           = lookup(ebs_block_device.value, "volume_type", null)
    }
  }

  dynamic "ephemeral_block_device" {
    for_each = var.ephemeral_block_device
    content {
      device_name  = ephemeral_block_device.value.device_name
      virtual_name = ephemeral_block_device.value.virtual_name
    }
  }

  dynamic "root_block_device" {
    for_each = var.root_block_device
    content {
      delete_on_termination = lookup(root_block_device.value, "delete_on_termination", null)
      iops                  = lookup(root_block_device.value, "iops", null)
      volume_size           = lookup(root_block_device.value, "volume_size", null)
      volume_type           = lookup(root_block_device.value, "volume_type", null)
      encrypted             = lookup(root_block_device.value, "encrypted", null)
    }
  }

  lifecycle {
    create_before_destroy = true
  }
}

#######################
# Launch template
#######################
resource "aws_launch_template" "this" {
  count = var.create_lc ? 1 : 0

  name_prefix   = "${coalesce(var.lc_name, var.name)}-"
  image_id      = var.image_id
  instance_type = ""
  key_name      = var.key_name
  user_data     = base64encode(var.user_data)
  ebs_optimized = var.ebs_optimized

  iam_instance_profile {
    name = var.iam_instance_profile
  }

  monitoring {
    enabled = var.enable_monitoring
  }

  placement {
    tenancy = var.placement_tenancy
  }

  network_interfaces {
    description                 = coalesce(var.lc_name, var.name)
    device_index                = 0
    associate_public_ip_address = var.associate_public_ip_address
    delete_on_termination       = true
    security_groups             = var.security_groups
  }

  dynamic "block_device_mappings" {
    for_each = var.block_device_mappings
    content {
      device_name  = lookup(block_device_mappings.value, "device_name", null)
      no_device    = lookup(block_device_mappings.value, "no_device", null)
      virtual_name = lookup(block_device_mappings.value, "virtual_name", null)

      dynamic "ebs" {
        for_each = lookup(block_device_mappings.value, "ebs", [])
        content {
          delete_on_termination = lookup(ebs.value, "delete_on_termination", null)
          encrypted             = lookup(ebs.value, "encrypted", null)
          iops                  = lookup(ebs.value, "iops", null)
          kms_key_id            = lookup(ebs.value, "kms_key_id", null)
          snapshot_id           = lookup(ebs.value, "snapshot_id", null)
          volume_size           = lookup(ebs.value, "volume_size", null)
          volume_type           = lookup(ebs.value, "volume_type", null)
        }
      }
    }
  }

  lifecycle {
    create_before_destroy = true
  }
}

####################
# Autoscaling group
####################
resource "aws_autoscaling_group" "this" {
  count = var.create_asg && false == var.create_asg_with_initial_lifecycle_hook ? 1 : 0

  name_prefix = "${join(
    "-",
    compact(
      [
        coalesce(var.asg_name, var.name),
        var.recreate_asg_when_lc_changes ? element(concat(random_pet.asg_new_name.*.id, [""]), 0) : "",
      ],
    ),
  )}-"
  vpc_zone_identifier = var.vpc_zone_identifier
  max_size            = var.max_size
  min_size            = var.min_size
  desired_capacity    = var.desired_capacity

  load_balancers            = var.load_balancers
  health_check_grace_period = var.health_check_grace_period
  health_check_type         = var.health_check_type

  min_elb_capacity          = var.min_elb_capacity
  wait_for_elb_capacity     = var.wait_for_elb_capacity
  target_group_arns         = var.target_group_arns
  default_cooldown          = var.default_cooldown
  force_delete              = var.force_delete
  termination_policies      = var.termination_policies
  suspended_processes       = var.suspended_processes
  placement_group           = var.placement_group
  enabled_metrics           = var.enabled_metrics
  metrics_granularity       = var.metrics_granularity
  wait_for_capacity_timeout = var.wait_for_capacity_timeout
  protect_from_scale_in     = var.protect_from_scale_in
  service_linked_role_arn   = var.service_linked_role_arn
  max_instance_lifetime     = var.max_instance_lifetime

  mixed_instances_policy {
    launch_template {
      launch_template_specification {
        launch_template_id = var.create_lc ? element(concat(aws_launch_template.this.*.id, [""]), 0) : var.launch_template
        version            = "$Latest"
      }

      dynamic "override" {
        for_each = var.instance_types
        content {
          instance_type     = lookup(override.value, "instance_type", null)
          weighted_capacity = lookup(override.value, "weighted_capacity", null)
        }
      }
    }

    instances_distribution {
      on_demand_base_capacity                  = var.on_demand_base_capacity
      on_demand_percentage_above_base_capacity = var.on_demand_percentage_above_base_capacity
      spot_allocation_strategy                 = var.spot_allocation_strategy
      spot_instance_pools                      = var.spot_allocation_strategy == "lowest-price" ? var.spot_instance_pools : null
      spot_max_price                           = var.spot_price
    }
  }

  dynamic "tag" {
    for_each = local.tags
    content {
      key                 = tag.value["key"]
      value               = tag.value["value"]
      propagate_at_launch = tag.value["propagate_at_launch"]
    }
  }

  lifecycle {
    create_before_destroy = true
  }

  depends_on = [aws_launch_template.this]
}

################################################
# Autoscaling group with initial lifecycle hook
################################################
resource "aws_autoscaling_group" "this_with_initial_lifecycle_hook" {
  count = var.create_asg && var.create_asg_with_initial_lifecycle_hook ? 1 : 0

  name_prefix = "${join(
    "-",
    compact(
      [
        coalesce(var.asg_name, var.name),
        var.recreate_asg_when_lc_changes ? element(concat(random_pet.asg_new_name.*.id, [""]), 0) : "",
      ],
    ),
  )}-"

  vpc_zone_identifier = var.vpc_zone_identifier
  max_size            = var.max_size
  min_size            = var.min_size
  desired_capacity    = var.desired_capacity

  load_balancers            = var.load_balancers
  health_check_grace_period = var.health_check_grace_period
  health_check_type         = var.health_check_type

  min_elb_capacity          = var.min_elb_capacity
  wait_for_elb_capacity     = var.wait_for_elb_capacity
  target_group_arns         = var.target_group_arns
  default_cooldown          = var.default_cooldown
  force_delete              = var.force_delete
  termination_policies      = var.termination_policies
  suspended_processes       = var.suspended_processes
  placement_group           = var.placement_group
  enabled_metrics           = var.enabled_metrics
  metrics_granularity       = var.metrics_granularity
  wait_for_capacity_timeout = var.wait_for_capacity_timeout
  protect_from_scale_in     = var.protect_from_scale_in
  service_linked_role_arn   = var.service_linked_role_arn

  mixed_instances_policy {
    launch_template {
      launch_template_specification {
        launch_template_id = var.create_lc ? element(concat(aws_launch_template.this.*.id, [""]), 0) : var.launch_template
        version            = "$Latest"
      }

      dynamic "override" {
        for_each = var.instance_types
        content {
          instance_type     = lookup(override.value, "instance_type", null)
          weighted_capacity = lookup(override.value, "weighted_capacity", null)
        }
      }
    }

    instances_distribution {
      on_demand_base_capacity                  = var.on_demand_base_capacity
      on_demand_percentage_above_base_capacity = var.on_demand_percentage_above_base_capacity
      spot_allocation_strategy                 = var.spot_allocation_strategy
      spot_instance_pools                      = var.spot_allocation_strategy == "lowest-price" ? var.spot_instance_pools : null
      spot_max_price                           = var.spot_price
    }
  }

  initial_lifecycle_hook {
    name                    = var.initial_lifecycle_hook_name
    lifecycle_transition    = var.initial_lifecycle_hook_lifecycle_transition
    notification_metadata   = var.initial_lifecycle_hook_notification_metadata
    heartbeat_timeout       = var.initial_lifecycle_hook_heartbeat_timeout
    notification_target_arn = var.initial_lifecycle_hook_notification_target_arn
    role_arn                = var.initial_lifecycle_hook_role_arn
    default_result          = var.initial_lifecycle_hook_default_result
  }

  dynamic "tag" {
    for_each = local.tags
    content {
      key                 = tag.value["key"]
      value               = tag.value["value"]
      propagate_at_launch = tag.value["propagate_at_launch"]
    }
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "random_pet" "asg_new_name" {
  count = var.recreate_asg_when_lc_changes ? 1 : 0

  separator = "-"
  length    = 2

  keepers = {
    # Generate a new pet name each time we switch launch configuration
    lc_name = var.create_lc ? element(concat(aws_launch_template.this.*.name, [""]), 0) : var.launch_configuration
  }

  depends_on = [aws_launch_template.this]

  lifecycle {
    create_before_destroy = true
  }
}
