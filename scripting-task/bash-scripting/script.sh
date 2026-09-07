#!/usr/bin/env bash


while IFS=',' read -r name email user_id || [[ -n "$name$email$user_id" ]]; do
name="$(echo "$name" | xargs)"
email="$(echo "$email" | xargs)"
user_id="$(echo "$user_id" | xargs)"

valid_fqdn=true

valid_user=true

if [[ -z "$email" || -z "$user_id" ]]; then
    echo "Warning: user '$name' missing required field"
    valid_user=false
fi

################# Email validation ###############

if [[ -n "$email" ]]; then

    if [[ "$email" != *@* || "$email" == *@*@* ]]; then
        echo "Warning: user '$name' invalid email format"
        valid_user=false
    fi

    IFS='@' read -r local_part domain <<< "$email"

    if [[ -z "$local_part" || -z "$domain" ]]; then
        echo "Warning: user '$name' invalid email format"
        valid_user=false
    fi


    IFS='.' read -ra labels <<< "$domain"

    if [[ ${#labels[@]} -lt 2 ]]; then
        valid_fqdn=false
    fi

    for label in "${labels[@]}"; do
        if [[ -z "$label" ]]; then
            valid_fqdn=false
            break
        fi

        if [[ ${#label} -gt 63 ]]; then
            valid_fqdn=false
            break
        fi

        if [[ "$label" == -* || "$label" == *- ]]; then
            valid_fqdn=false
            break
        fi

        if [[ ! "$label" =~ ^[A-Za-z0-9-]+$ ]]; then
            valid_fqdn=false
            break
        fi
    done

    if [[ "$valid_fqdn" == false ]]; then
        echo "Warning: user '$name' email domain is not a valid FQDN"
        valid_user=false
    fi

    if [[ "$valid_fqdn" == true ]]; then

        mx_records="$(dig +short MX "$domain")"

        if [[ -z "$mx_records" ]]; then
            echo "Warning: user '$name' domain has no MX record, user doesn't have a routable email address"
            valid_user=false
        fi

        if [[ "$mx_records" == "0 ." ]]; then
            echo "Warning: user '$name' domain does not accept email"
            valid_user=false
        fi
    fi
fi

if [[ -n "$user_id" ]]; then
    if [[ ! "$user_id" =~ ^[0-9]+$ ]]; then
        echo "Warning: user '$name' invalid user ID"
        valid_user=false
    fi
fi


if [[ "$valid_user" == false ]]; then
    continue
fi

if (( user_id % 2 == 0 )); then
    parity="even"
else
    parity="odd"
fi


echo "The user_ID: $user_id of email: $email is $parity number."

done < users.txt

