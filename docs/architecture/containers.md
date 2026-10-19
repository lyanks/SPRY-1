# Container diagram (C4, level 2) - after Lab 6

Updated in Lab 6: the **agenda parser** function and **Amazon Bedrock**, with the two arrows that
matter - *parse* (browser -> parser -> Bedrock) and *save* (browser -> API -> database).

```mermaid
flowchart LR
  person(["Person<br/>(signed in)"])

  subgraph browser["Browser"]
    web["Spry web app<br/>Next.js static export"]
  end

  cf["CloudFront + S3<br/>serves the web app"]
  cognito["Amazon Cognito<br/>sign-in, access tokens"]

  subgraph vpc["VPC (no NAT)"]
    api["Spry API<br/>FastAPI on ECS Fargate"]
    db[("PostgreSQL<br/>meetings, agenda,<br/>ai_suggestion")]
    builder["report-builder<br/>Lambda"]
  end

  parser["agenda-parser<br/>Lambda, outside the VPC<br/>(function URL)"]
  bedrock["Amazon Bedrock<br/>Claude"]
  reports["S3 reports -> mailer Lambda -> SES"]

  person --> web
  cf -. "serves" .-> web
  web -- "sign in" --> cognito
  web -- "1. parse: pasted text + token" --> parser
  parser -- "2. record_agenda tool call" --> bedrock
  parser -. "verifies the token<br/>with Cognito's keys" .-> cognito
  parser -- "3. validated JSON (a suggestion)" --> web
  web -- "4. save: the checked form + ai_suggestion" --> api
  api --> db
  builder --> db
  builder --> reports
```

Reading it: the parser never touches the database and never writes anything. The only way data
changes is the *save* arrow, through the API that was already there.
