.odb_cloud_spec_redshift <- function() {
  list(
    title = "Amazon Redshift",
    purpose = "Query Redshift as the person who signs in through Microsoft Entra. This example uses an external JWT and Redshift's IAM Identity Center trusted-token integration.",
    account_url = "https://docs.aws.amazon.com/redshift/latest/gsg/getting-started.html",
    setup_url = "https://docs.aws.amazon.com/redshift/latest/mgmt/redshift-iam-access-control-idp-connect-oauth.html",
    registration_url = "https://docs.aws.amazon.com/singlesignon/latest/userguide/setuptrustedtokenissuer.html",
    registration = c(
      "An AWS account or database endpoint alone is not enough. Your AWS administrator must integrate Redshift with IAM Identity Center and configure Microsoft Entra as a trusted token issuer, including the accepted audience and user attribute mapping.",
      "In Entra, an administrator exposes an API resource with a delegated scope for this integration. Register the Shiny client in the same tenant, give it that delegated permission, and grant consent as required. Copy the resource's Application ID URI and full scope; these are not the Redshift hostname or an AWS access key.",
      "Register the callback below under Mobile and desktop applications for public PKCE, or Web for a confidential client. Copy Application (client) ID and Directory (tenant) ID; a confidential registration also needs its secret through masked input or OAUTHDB_REDSHIFT_CLIENT_SECRET.",
      "Grant the IAM Identity Center users/groups appropriate Redshift database privileges. Verify trusted identity propagation and the JWT aud/issuer mapping with your administrators. This app uses IdpTokenAuthPlugin with EXT_JWT, not AWS console sign-in, SAML, ACCESS_TOKEN or SUBJECT_TOKEN flows."
    ),
    cost = "Queries can use Redshift compute or trial credits. Stopping this app does not pause a cluster, delete a workgroup or cancel cloud charges.",
    client_types = c("public", "confidential"),
    packages = list(odbc = "1.4.2"),
    driver_url = "https://docs.aws.amazon.com/redshift/latest/mgmt/odbc20-install.html",
    readiness = "identity_center_ready",
    validate = .odb_cloud_resource_scope,
    required = c(
      "identity_center_ready",
      "server",
      "database",
      "tenant_id",
      "resource",
      "scope",
      "client_id"
    ),
    fields = list(
      identity_center_ready = .odb_cloud_field(
        "Check the Redshift sign-in integration",
        "Has your administrator configured Redshift with IAM Identity Center and Entra as a trusted token issuer? 1: Yes; 2: Not ready yet (save a draft with setup links).",
        "ready"
      ),
      server = .odb_cloud_field(
        "Find the Redshift endpoint",
        "In the AWS Redshift console, open the cluster or serverless workgroup and copy its endpoint hostname without the port. This computer must have network access through the VPC/security-group configuration.",
        "hostname"
      ),
      database = .odb_cloud_field(
        "Find the database name",
        "Copy the database name from the cluster/workgroup connection settings, often dev. Use a database the mapped users/groups can access.",
        "odbc"
      ),
      tenant_id = .odb_cloud_tenant_field(),
      resource = .odb_cloud_resource_field(),
      scope = .odb_cloud_scope_field(),
      database_port = .odb_cloud_field(
        "Redshift TCP port",
        "Copy the database port from the endpoint. The default is 5439; supply database_port if different.",
        "port",
        "5439"
      ),
      driver = .odb_cloud_field(
        "Redshift ODBC driver",
        "Install the AWS Redshift ODBC 2.x driver with IdpTokenAuthPlugin. Supply driver if its registered name differs on your operating system.",
        "odbc",
        "Amazon Redshift (x64)"
      )
    )
  )
}
