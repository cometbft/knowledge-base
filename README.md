# CometBFT Knowledge Base

[![Creative Commons Attribution 4.0 International
License][license-img]][license]

This repository is intended to act as a team [Zettelkasten][zk] for the CometBFT
core team as an attempt to preserve both knowledge gained and insights gleaned
by the team - both for the current team, and future people working on the
project.

It is _always_ a work-in-progress. It is made public in case other people or
users may find it to be of use/interest.

## Requirements

At present, [Foam] is used for editing and navigating the content - this may
change in future as the team explores different tools for managing the knowledge
base.

## Structure

This knowledge base is very loosely organized, and is intended to be seen as a
graph of interrelated notes/ideas/concepts.

- The directory structure does not matter very much, as all content is loaded
  recursively by the tooling.
- Create one Markdown document per logical concept.
- If a logical concept is very complex, try to break it down into interrelated
  concepts.
- Link from one concept to related concepts using `[[link]]` syntax, such that
  the tooling will pick up on these links and generate a navigable knowledge
  graph.
- Use standard Markdown links to reference source material.

## Contributing

Core team members can make updates directly to the `main` branch without
submitting pull requests. Only if you feel you need content to be reviewed
should you submit a pull request.

For non-core team contributors:
- If you find a mistake in any of the concepts you encounter in this repository,
  please submit an issue.
- If you would like to add concepts, or expand on them in some way, please
  submit a pull request. Please limit the addition of new concepts to **one
  concept per pull request**. In general, the smaller and more concise a pull
  request (< 300-500 lines), the quicker it will be for the core team to review
  and the more likely it is to be accepted.

## License

This work is licensed under a [Creative Commons Attribution 4.0 International
License][license].

[zk]: https://en.wikipedia.org/wiki/Zettelkasten
[Foam]: https://foambubble.github.io/foam/
[license]: https://creativecommons.org/licenses/by/4.0/
[license-img]: https://i.creativecommons.org/l/by/4.0/80x15.png
