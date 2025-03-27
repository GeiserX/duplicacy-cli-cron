# Duplicacy CLI (Cron)

This project was started when any single duplicacy CLI docker container couldn't appropriately fit my needs.

The aim of this project is to have cron enabled in order to perform backups from multiple locations to multiple different storages, without the hassle of spinning up several docker containers.

In order to approach a higher reliability, a script is left in `/etc/periodic/daily` per duplicacy location is created. The locations have been selected as well in order to minimize RTO (Recovery Time Objective).

The location examples are primarily meant for UnRAID users, but they can be tailored to fit your needs.

The logs are configured to be available for tracking with `docker logs CONTAINER_NAME`.

## Set-up

### Configuration files

Execute the script named `config.sh` under the folder `config` of this repository per configured location.

Save each script to `/config/${MY-LOCATION}-config.sh` within the pod so that you can benefit from having it backed up as well, in case of a future disaster. Execute it before following to the next step. Don't forget to `chmod +x ${MY-LOCATION}-config.sh`.

If something happens during the setup process (With duplicacy, that's a guarantee, for sure) you can safely delete `rm -rf .duplicacy/` on the local folder which is having problems, then re-execute this config file. You could have this in another file called `reinit-folders.sh` which you can find under `config` folder in the repository.

### Script files

You can find an example of a script file under the `scripts` folder of the repository

Save it to `/etc/periodic/daily/${MY_LOCATION}-script` (NOTE: without `.sh`) within the container to perform daily backups, do not forget to `chmod +x ${MY-LOCATION}-script`. Crontab is already configured thanks to the `busybox-openrc` package. If you want to change the timings for the daily backups, modify at wish with `crontab -e`. You can also modify the SHOUTRRR URL as desired.

## Maintainers

[@GeiserX](https://github.com/GeiserX).

## Contributing

Feel free to dive in! [Open an issue](https://github.com/GeiserX/duplicacy-cli-cron/issues/new) or submit PRs.

Duplicacy CLI (Cron) follows the [Contributor Covenant](http://contributor-covenant.org/version/2/1/) Code of Conduct.

### Contributors

This project exists thanks to all the people who contribute. 
<a href="https://github.com/GeiserX/duplicacy-cli-cron/graphs/contributors"><img src="https://opencollective.com/duplicacy-cli-cron/contributors.svg?width=890&button=false" /></a>

