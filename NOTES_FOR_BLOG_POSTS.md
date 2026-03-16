# Notes for blog posts

# FIXME: LEFT OFF HERE: ----------

# VERY CLEARLY describe my approach to AI in this game
# - Include this call-out at the top of each post (and/or maybe make a separate post detailing this and link to it from the blurb, which has a condensed summary).
# - I wrote the original (robust) client/server rollback netcode implementation with no AI assistance.
# - I later added the _entire_ backend, most of the current UI, and various bells and whistles with AI assistance.
# - I also wrote the original tileset-based level art with no AI assistance.
# - I wrote all animations with no AI assistance.
# - I used Stable Diffusion with ControlNet to generate the foundations of my level art. I then adjusted this by hand.

## Post: Stable Diffusion for 2D platformer art

- With PixelLab?

## Post: The Netcode rollback plugin

-

## Post: AWS GameLift and GDExtension

- Why I chose this architecture.

## Claude Code for hands-free distributed systems with AWS

- I _always_ use `--dangerously-skip-permissions` now for the Claude code session that's handling backend changes.
- Otherwise, Claude needs too many interruptions for permissions to check-on or execute things on the backend or server. And I've _never_ seen a time where I'd want to say no.





