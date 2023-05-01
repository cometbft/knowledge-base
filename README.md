# CometBFT Knowledge Base

[![Creative Commons Attribution 4.0 International
License][license-img]][license]

This repository is intended to act as a team [Zettelkasten][zk] for the CometBFT
core team. It is _always_ a work-in-progress. It is made public in case other
people or users may find it to be of use/interest.

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

## License

This work is licensed under a [Creative Commons Attribution 4.0 International
License][license].

[zk]: https://en.wikipedia.org/wiki/Zettelkasten
[Foam]: https://foambubble.github.io/foam/
[license]: https://creativecommons.org/licenses/by/4.0/
[license-img]: https://i.creativecommons.org/l/by/4.0/80x15.png
