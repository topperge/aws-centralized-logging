#==============================================================================
# Cognito authentication for Kibana
#==============================================================================
resource "aws_cognito_user_pool" "es" {
  name                     = "${var.name_prefix}-${var.domain_name}-users"
  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]
  user_pool_tier           = var.cognito_advanced_security_mode == "OFF" ? "ESSENTIALS" : "PLUS"

  schema {
    name                = "email"
    attribute_data_type = "String"
    required            = true
    mutable             = true

    string_attribute_constraints {
      min_length = 0
      max_length = 2048
    }
  }

  password_policy {
    minimum_length                   = 8
    require_lowercase                = true
    require_uppercase                = true
    require_numbers                  = true
    require_symbols                  = true
    temporary_password_validity_days = 3
  }

  admin_create_user_config {
    allow_admin_create_user_only = true
  }

  account_recovery_setting {
    recovery_mechanism {
      name     = "verified_email"
      priority = 1
    }
  }

  user_pool_add_ons {
    advanced_security_mode = var.cognito_advanced_security_mode
  }
}

resource "aws_cognito_user_pool_domain" "es" {
  domain       = "${var.domain_name}-${local.uuid}"
  user_pool_id = aws_cognito_user_pool.es.id
}

resource "aws_cognito_user" "admin" {
  user_pool_id             = aws_cognito_user_pool.es.id
  username                 = var.admin_email
  desired_delivery_mediums = ["EMAIL"]

  attributes = {
    email = var.admin_email
  }
}

resource "aws_cognito_identity_pool" "es" {
  # Identity pool names only allow word characters and spaces.
  identity_pool_name               = "${var.name_prefix}_${replace(var.domain_name, "-", "_")}_identities"
  allow_unauthenticated_identities = false

  lifecycle {
    # The domain registers its own Cognito app client as an identity provider.
    ignore_changes = [cognito_identity_providers]
  }
}

#------------------------------------------------------------------------------
# Authenticated role for Kibana users
#------------------------------------------------------------------------------
data "aws_iam_policy_document" "cognito_auth_assume" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = ["cognito-identity.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "cognito-identity.amazonaws.com:aud"
      values   = [aws_cognito_identity_pool.es.id]
    }
    condition {
      test     = "ForAnyValue:StringLike"
      variable = "cognito-identity.amazonaws.com:amr"
      values   = ["authenticated"]
    }
  }
}

resource "aws_iam_role" "cognito_auth" {
  name_prefix        = "${var.name_prefix}-CognitoAuth-"
  assume_role_policy = data.aws_iam_policy_document.cognito_auth_assume.json
}

data "aws_iam_policy_document" "cognito_auth" {
  statement {
    actions = [
      "es:ESHttpGet",
      "es:ESHttpDelete",
      "es:ESHttpPut",
      "es:ESHttpPost",
      "es:ESHttpHead",
      "es:ESHttpPatch",
    ]
    resources = [aws_opensearch_domain.es.arn]
  }
}

resource "aws_iam_role_policy" "cognito_auth" {
  name   = "authRolePolicy"
  role   = aws_iam_role.cognito_auth.id
  policy = data.aws_iam_policy_document.cognito_auth.json
}

resource "aws_cognito_identity_pool_roles_attachment" "es" {
  identity_pool_id = aws_cognito_identity_pool.es.id

  roles = {
    authenticated = aws_iam_role.cognito_auth.arn
  }
}

#------------------------------------------------------------------------------
# Role the domain uses to configure Cognito (same as AmazonESCognitoAccess)
#------------------------------------------------------------------------------
data "aws_iam_policy_document" "es_cognito_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["es.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "es_cognito" {
  name_prefix        = "${var.name_prefix}-ESCognito-"
  assume_role_policy = data.aws_iam_policy_document.es_cognito_assume.json
}

data "aws_iam_policy_document" "es_cognito" {
  statement {
    actions = [
      "cognito-idp:DescribeUserPool",
      "cognito-idp:CreateUserPoolClient",
      "cognito-idp:DeleteUserPoolClient",
      "cognito-idp:DescribeUserPoolClient",
      "cognito-idp:AdminInitiateAuth",
      "cognito-idp:AdminUserGlobalSignOut",
      "cognito-idp:ListUserPoolClients",
      "cognito-identity:DescribeIdentityPool",
      "cognito-identity:UpdateIdentityPool",
      "cognito-identity:SetIdentityPoolRoles",
      "cognito-identity:GetIdentityPoolRoles",
    ]
    resources = ["*"]
  }
  statement {
    actions   = ["iam:PassRole"]
    resources = [aws_iam_role.es_cognito.arn]
    condition {
      test     = "StringLike"
      variable = "iam:PassedToService"
      values   = ["cognito-identity.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy" "es_cognito" {
  name   = "ESCognitoAccess"
  role   = aws_iam_role.es_cognito.id
  policy = data.aws_iam_policy_document.es_cognito.json
}
