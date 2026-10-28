# Non-secret values, copied from the CloudFormation stacks by scripts/tf-vars.sh.
# google_client_secret is NOT here: it is a sensitive variable of the HCP Terraform workspace.
project_name               = "spry"
region                     = "eu-north-1"
site_url                   = "https://d1iw5vcxqhrukw.cloudfront.net"
google_client_id           = "727054397924-lfr38fkvvvm31irpjkk4itnetu2i7nbi.apps.googleusercontent.com"
image_uri                  = "818566829750.dkr.ecr.eu-north-1.amazonaws.com/spry-backend:reports-11e198488bd4"
vpc_id                     = "vpc-0bcbf4eea4d52ed91"
subnet_ids                 = ["subnet-0b35025164914401b", "subnet-07bef8e89628025b6", "subnet-0baf506a566eae02f"]
route_table_ids            = ["rtb-0fca65448f2aa7a4e"]
database_security_group_id = "sg-083a243265481e808"
database_host              = "spry-db.chsicsqimrbp.eu-north-1.rds.amazonaws.com"
report_email               = "ulyana.kryshchuk@gmail.com"
schedule_expression        = "cron(0 7 ? * MON *)"
fail_week                  = ""
parser_image_uri           = "818566829750.dkr.ecr.eu-north-1.amazonaws.com/spry-backend:ai-aefcf9596ae4"
allowed_origins            = ["http://localhost:3000", "https://d1iw5vcxqhrukw.cloudfront.net"]
parser_model               = "us.anthropic.claude-haiku-4-5-20251001-v1:0"
parser_api                 = "runtime"
parser_effort              = ""
bedrock_region             = "us-east-1"
