# verdaccio-railway

Deployment image for running [Verdaccio](https://verdaccio.org) — a lightweight
private npm proxy registry — on [Railway](https://railway.com).

One layer on top of `verdaccio/verdaccio:6`. It exists because a Railway
deployment differs from `docker run` in three ways:

- the attached volume arrives root-owned, while the image runs as uid `10001`;
- the registry is configured by a YAML file, not by environment variables;
- self-registration is switched off, so the first account has to be created
  before anyone can log in.

`entrypoint.sh` runs as root, prepares the volume, renders
`config.template.yaml` into `/verdaccio/conf/config.yaml`, seeds the operator's
account into an `htpasswd` file on the volume, then drops to uid `10001` and
hands over to the image's own entrypoint.

## Variables

| Variable | Default | Purpose |
|---|---|---|
| `VERDACCIO_ADMIN_USER` | `admin` | Registry account seeded at boot |
| `VERDACCIO_ADMIN_PASSWORD` | — | Its password. Re-seeded only when the pair changes, so a password rotated through `npm profile` survives redeploys |
| `VERDACCIO_PACKAGE_ACCESS` | `$authenticated` | Who may read packages. Set to `$all` for a public read-only mirror |
| `VERDACCIO_MAX_USERS` | `-1` | Self-registration limit. `-1` disables `npm adduser`; raise it to let people sign up |
| `VERDACCIO_UPLINK_URL` | `https://registry.npmjs.org/` | Upstream registry proxied and cached |
| `VERDACCIO_PUBLIC_URL` | — | Public base URL, so tarball links point at the domain rather than the container |
| `VERDACCIO_DATA_DIR` | `/data` | Volume mount path |
| `VERDACCIO_PORT` / `PORT` | `4873` | Listen port |

## Usage

```bash
npm login  --registry https://<your-domain>
npm publish --registry https://<your-domain>
npm install --registry https://<your-domain>
```
