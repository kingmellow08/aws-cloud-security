# Bootstrap creates the S3 bucket every other root module stores its state in,
# so it cannot keep its own state there on the first apply. It uses local
# state, which must be protected as described in
# docs/terraform-state-ownership.md ("Protecting the bootstrap state").
terraform {
  backend "local" {
    path = "terraform.tfstate"
  }
}
