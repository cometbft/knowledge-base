# CometBFT Knowledge Base

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
  please submit an issue, or a pull request that addresses the mistake.
- If you would like to add concepts, or expand on them in some way, please
  submit a pull request. Please limit the addition of new concepts to **one
  concept per pull request**. In general, the smaller and more concise a pull
  request (< 300-500 lines), the quicker it will be for the core team to review
  and the more likely it is to be accepted.

## License

Copyright 2023 Informal Systems Inc. and contributors

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

[zk]: https://en.wikipedia.org/wiki/Zettelkasten
[Foam]: https://foambubble.github.io/foam/
