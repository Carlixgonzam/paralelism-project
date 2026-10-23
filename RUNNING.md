# Running a race locally

This page shows how to run the platform on your PC and race your crawler. Run every
command from the repo root.

## Requirements

- Docker, with the `docker compose` and `docker buildx` commands. Recent Docker
  installations include both.
- `make` and `curl`.
- Free disk space: 2.2 GB for the Wikipedia snapshot, plus the Docker images.
- Optional: Elixir 1.20.2 and Erlang 28.5 (see `.tool-versions`), to run `mix test` in
  `player/`.

## 1. Start everything

```
make up
```

The first time, this downloads the Wikipedia snapshot and builds the images. It takes a
while. Then four containers start:

| Container            | What it does                                             |
| -------------------- | -------------------------------------------------------- |
| `kiwix1`             | Serves the offline Wikipedia at <http://localhost:8080>. |
| `platform`           | The harness, the admin page and the dashboard.           |
| `player1`, `player2` | Two nodes. Both run your `player/` folder.               |

Useful commands:

| Command                          | What it does                        |
| -------------------------------- | ----------------------------------- |
| `make down`                      | Stops everything.                   |
| `make logs`                      | Shows the output of all containers. |
| `docker compose logs -f player1` | Shows the output of your crawler.   |

Always use `make up` to build and start. Do not use `docker compose build`. It fails on
recent versions of Docker.

## 2. Check the setup

1. Open the admin page: <http://localhost:4000/admin>.
2. Check that the next match is `player1 vs player2`.
3. Click "Start race".

Before you write your crawler, the race does not start. The admin page shows an error
like this one:

```
player1: start/2 unreachable: ...; player2: start/2 unreachable: ...
```

This is correct. It means the platform can reach both player nodes.

If the admin page does not show `player1 vs player2`, something is wrong. Run `make logs`
and fix it before you write any code.

## 3. Race your crawler

1. Write your crawler. `player/README.md` explains what to implement.
2. Restart the player containers, so they compile your code:

   ```
   docker compose restart player1 player2
   ```

3. On the admin page, click "Restart tournament" (at the bottom of the page).
4. Click "Start race".
5. Watch the race on the dashboard: <http://localhost:4000>.

The local tournament has only one match, so you must click "Restart tournament" before
every race. You can also choose another pair of articles from the list on the admin
page.

## Snapshots

By default, `make up` uses a small copy of Wikipedia. Competition day uses the full one.

| Snapshot (`KIWIX_BOOK`)            | Size   | Use                                              |
| ---------------------------------- | ------ | ------------------------------------------------ |
| `wikipedia_en_top_nopic` (default) | 2.2 GB | Daily work. Real links between articles.         |
| `wikipedia_en_all_nopic`           | 52 GB  | Competition day. The full Wikipedia.             |
| `wikipedia_en_100_nopic`           | 15 MB  | Only to check the setup. Most links are missing. |

To use another snapshot, add it to `make up`:

```
make up KIWIX_BOOK=wikipedia_en_all_nopic
```

Use the same `KIWIX_BOOK` every time you run `make up`.

If you already downloaded a snapshot, copy it to `.data/zim/` with the name
`<KIWIX_BOOK>.zim`, without a date. For example, `.data/zim/wikipedia_en_all_nopic.zim`.
Then `make up` does not download it again.

Pages in the full snapshot have many more links. Test your crawler on it before
competition day if you can.
