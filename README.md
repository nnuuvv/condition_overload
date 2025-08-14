# condition_overload

Wiki search for [Condition Overload (Mechanic)](https://wiki.warframe.com/w/Condition_Overload_(Mechanic)) 

Made for use in twitch bots. Using [MixItUp](https://mixitupapp.com)'s [external program action](https://wiki.mixitupapp.com/en/actions/external-program-action).

### Example:

`!gunCO braton`
in chat, runs:
`[path-to]/condition_overload braton`
which prints:
`The 'Braton Vandal / Braton Prime / MK1-Braton / Braton' 'Incarnon Form Radial Attack AoE' has a poor interaction with GunCO.`
into standard out, to be sent as a response.


## Development

```sh
gleam run SEARCHTERM   # Run the project
```

## Build

```sh
docker build --output ./build/bin/ .
```

