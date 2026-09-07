import dns.resolver

with open ("users.txt", "r") as file:
    for line in file:
        fields = line.strip().split(",")

        valid_fqdn = True
        valid_user = True
        valid_email = True

        if len(fields) != 3:
            print(f"Warning: user '{name}' invalid number of fields")
            continue

        name = fields[0].strip()
        email = fields[1].strip()
        user_id = fields[2].strip()

        if  not email:
            print(f"Warning: user '{name}' missing email")
            valid_user = False
            valid_email = False

        if  not user_id:
            print(f"Warning: user '{name}' missing user ID")
            valid_user = False

        email_parts = email.split("@")

        if len(email_parts) != 2 or not email_parts[0] or not email_parts[1]:
            print(f"Warning: user '{name}' invalid email format")
            valid_user = False
            valid_email = False

        if valid_email:

            local_part, domain = email_parts

            labels = domain.split(".")


            if len(labels) < 2:
                valid_fqdn = False

            for label in labels:
                if not label:
                    valid_fqdn = False
                    break

                if len(label) > 63:
                    valid_fqdn = False
                    break

                if label.startswith("-") or label.endswith("-"):
                    valid_fqdn = False
                    break

                if not all(char.isalnum() or char == "-" for char in label):
                    valid_fqdn = False
                    break

            if not valid_fqdn:
                print(f"Warning: user '{name}' email domain is not a valid FQDN")
                valid_user = False

        if valid_email and valid_fqdn:

            try:
                mx_records = dns.resolver.resolve(domain, "MX")

            except dns.resolver.NXDOMAIN:
                print(f"Warning: user '{name}' domain does not exist, user doesn't have a routable email address")
                valid_user = False

            except dns.resolver.NoAnswer:
                print(f"Warning: user '{name}' domain has no MX record, user doesn't have a routable email address")
                valid_user = False

            except dns.resolver.NoNameservers:
                print(f"Warning: user '{name}' DNS lookup failed, user doesn't have a routable email address")
                valid_user = False


        if user_id:
            try:
                user_id = int(user_id)
            except ValueError:
                print(f"Warning: user '{name}' invalid user ID")
                valid_user = False

            if not valid_user:
                continue

            if user_id % 2 == 0:
                parity = "even"
            else:
                parity = "odd"

            print(f"The user_ID: {user_id} of email: {email} is {parity} number.")