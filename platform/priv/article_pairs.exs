# The pool of start and target articles races are drawn from.
#
# Pairs are curated rather than random on purpose. Two random articles are
# often either three hops apart or not connected at all, and neither makes for
# a race worth watching.
#
# Titles are written the readable way, with spaces, and must match the article
# in the snapshot. Vet the pool against the running Kiwix instance with:
#
#     WikiRacePlatform.Articles.check_pairs()
#
# Every title below is also in the small `wikipedia_en_100_nopic` snapshot, so
# the same pool works whether you are developing against that or racing on the
# full one. Edits take effect on the next race, no restart needed.
#
# This is the real pool: a manual race picks one from a dropdown on
# `/admin`, and a tournament's rounds step through a configured sequence
# from it (`round_pairs` in `config/config.exs`). Before a real
# tournament, vet and time any new pairs against the full snapshot first,
# since a pair that looks fine on a small snapshot can behave very
# differently at full scale.

[
  %{
    start: "Tiger",
    target: "Antarctica",
    note: "short and reliable, good for a demo"
  },
  %{
    start: "Bird",
    target: "Nelson Mandela",
    note: "nature to politics, plenty of routes"
  },
  %{
    start: "Antarctica",
    target: "The Beatles",
    note: "geography to culture"
  },
  %{
    start: "Enzyme",
    target: "Hong Kong",
    note: "biology to geography, rewards a wide frontier"
  },
  %{
    start: "Leopard",
    target: "YouTube",
    note: "no obvious link"
  },
  %{
    start: "Solar eclipse",
    target: "Spanish language",
    note: "science to language"
  },
  %{
    start: "Dinosaur",
    target: "Video game",
    note: "crowd pleaser, usually a few hops"
  },
  %{
    start: "Maya civilization",
    target: "Protein",
    note: "history to chemistry, punishes a depth-first search"
  },
  %{
    start: "Old Trafford",
    target: "Virus",
    note: "narrow start, tests raw throughput"
  },
  %{
    start: "Raccoon",
    target: "Elizabeth II",
    note: "long enough to separate the two crawlers"
  },
  %{
    start: "Whisk",
    target: "Shoehorn",
    note: "a slow, heavy pair, good for stress-testing a crawler"
  }
]
