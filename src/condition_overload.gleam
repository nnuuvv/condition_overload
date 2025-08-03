import argv
import gleam/fetch
import gleam/http/request
import gleam/io
import gleam/javascript/promise
import gleam/list
import gleam/pair
import gleam/result
import gleam/string
import splitter

pub fn main() {
  let assert Ok(search) =
    argv.load().arguments
    |> list.first()
    as "search has to be supploed as argument"
  let search = string.lowercase(search)

  let _ =
    [
      "https://wiki.warframe.com/w/Condition_Overload_%28Mechanic%29?action=edit&section=7",
      "https://wiki.warframe.com/w/Condition_Overload_%28Mechanic%29?action=edit&section=8",
    ]
    |> list.map(do_request)
    |> promise.await_list()
    |> promise.map(result.values)
    |> promise.map(list.flatten)
    |> promise.map(
      list.find(_, fn(item) {
        item.names
        |> list.any(fn(name) {
          let lower = string.lowercase(name)
          string.contains(lower, search)
        })
      }),
    )
    |> promise.map(fn(x) { io.print(string.inspect(x)) })
}

// do request and return Row if successful
// 
fn do_request(
  url: String,
) -> promise.Promise(Result(List(Row), fetch.FetchError)) {
  let assert Ok(req) = request.to(url)

  // Send the HTTP request to the server
  use resp <- promise.try_await(fetch.send(req))
  use resp <- promise.try_await(fetch.read_text_body(resp))

  let rows =
    resp.body
    |> get_text_area()
    |> result.map(parse_text_area)
    |> result.unwrap([])

  promise.resolve(Ok(rows))
}

// discards the html and returns only the raw text from the textarea
//
fn get_text_area(html_text: String) -> Result(String, Nil) {
  html_text
  // trim to start of textarea
  |> string.split_once("<textarea")
  |> result.map(pair.second)
  // remove rest of tag
  |> result.try(string.split_once(_, "\">"))
  |> result.map(pair.second)
  // remove stuff after
  |> result.try(string.split_once(_, "</textarea>"))
  |> result.map(pair.first)
}

fn parse_text_area(textarea: String) {
  textarea
  |> string.split("\n")
  |> list.map(string.trim)
  |> process_lines([])
}

pub type Row {
  Row(
    names: List(String),
    attack: String,
    projectile: String,
    base_damage: String,
    co_bonus_at_100: String,
    co_bonos_rel_base: String,
    math_behavior: String,
    notes: String,
  )
}

// Parse single line entires into Row type
//
// !Weapon!!Attack Name!!Projectile Type!!Attack Unmodded Damage!!Actual CO Damage Bonus at +100%!!CO Damage Bonus Relative To Base Damage!!Math/Behavior Type!!Notes
//
// single name
//
// |{{Weapon|Ambassador}}||Alt-fire Hitscan AoE||AoE||800||600||75%||Adding||Radial hit only receives CO bonus on target directly hit by laser. CO-bonus scales off hitscan damage. AoE does not scale off multishot.
//
// multi name
//
// |{{Weapon|Braton}}/{{Weapon|MK1-Braton|MK1}}/{{Weapon|Braton Prime|Prime}}/{{Weapon|Braton Vandal|Vandal}}||Incarnon Form AoE||AoE||74||70||95%||Adding||Listed values for Braton Prime with inactive Daring Reverie. Radial hit only receives CO bonus on target directly hit by bullet. AoE does not scale off multishot.
//
fn parse_line(line: String) -> Row {
  let #(names, rest) = parse_names(line, [])

  let sep = splitter.new(["||"])

  let #(attack, _, rest) = splitter.split(sep, rest)
  let #(projectile, _, rest) = splitter.split(sep, rest)
  let #(base_damage, _, rest) = splitter.split(sep, rest)
  let #(co_bonus_at_100, _, rest) = splitter.split(sep, rest)
  let #(co_bonos_rel_base, _, rest) = splitter.split(sep, rest)
  let #(math_behavior, _, rest) = splitter.split(sep, rest)
  let #(notes, _, _) = splitter.split(sep, rest)
  Row(
    names:,
    attack:,
    projectile:,
    base_damage:,
    co_bonus_at_100:,
    co_bonos_rel_base:,
    math_behavior:,
    notes:,
  )
}

// Parse data line by line from the following formats: 
//
// !Weapon!!Attack Name!!Projectile Type!!Attack Unmodded Damage!!Actual CO Damage Bonus at +100%!!CO Damage Bonus Relative To Base Damage!!Math/Behavior Type!!Notes
//
// single name - one line
//
// |{{Weapon|Ambassador}}||Alt-fire Hitscan AoE||AoE||800||600||75%||Adding||Radial hit only receives CO bonus on target directly hit by laser. CO-bonus scales off hitscan damage. AoE does not scale off multishot.
// |-
//
// multi name - one line
//
// |{{Weapon|Braton}}/{{Weapon|MK1-Braton|MK1}}/{{Weapon|Braton Prime|Prime}}/{{Weapon|Braton Vandal|Vandal}}||Incarnon Form AoE||AoE||74||70||95%||Adding||Listed values for Braton Prime with inactive Daring Reverie. Radial hit only receives CO bonus on target directly hit by bullet. AoE does not scale off multishot.
// |-
// 
// multi line - single & multi name
//
// |{{Weapon|Evensong}}
// |Charged Radial Attack
// |AoE
// |150
// |0
// |0%
// |N/A
// |Does not apply
// |-
// 
// into row type
//
// |-
//
fn process_lines(lines: List(String), acc: List(Row)) -> List(Row) {
  case lines {
    ["|{{Weapon|" <> name_line, ..rest] -> {
      let row = case rest {
        ["|-", ..] -> {
          parse_line(name_line)
        }
        [] | _ -> {
          let #(names, _) = parse_names(name_line, [])
          let row = parse_values_vertical(names, rest)
          row
        }
      }

      process_lines(rest, [row, ..acc])
    }
    [_, ..rest] -> process_lines(rest, acc)
    [] -> acc
  }
}

// multi line - single & multi name
//
// |{{Weapon|Evensong}}
// |Charged Radial Attack
// |AoE
// |150
// |0
// |0%
// |N/A
// |Does not apply
// |-
//
fn parse_values_vertical(names: List(String), lines: List(String)) -> Row {
  let #(attack, rest) = parse_value(lines)
  let #(projectile, rest) = parse_value(rest)
  let #(base_damage, rest) = parse_value(rest)
  let #(co_bonus_at_100, rest) = parse_value(rest)
  let #(co_bonos_rel_base, rest) = parse_value(rest)
  let #(math_behavior, rest) = parse_value(rest)
  let #(notes, _) = parse_value(rest)

  Row(
    names:,
    attack:,
    projectile:,
    base_damage:,
    co_bonus_at_100:,
    co_bonos_rel_base:,
    math_behavior:,
    notes:,
  )
}

// read values one at a time until the next |-
//
fn parse_value(lines: List(String)) {
  case lines {
    ["|-", ..] -> #("", lines)
    ["|" <> value, ..rest] -> #(value, rest)
    [] | [_] | [_, _, ..] -> #("", lines)
  }
}

// process the weapon names 
//
fn parse_names(line: String, acc) {
  let sep = splitter.new(["}}/{{Weapon|", "}}/{{Weapon", "}}||", "}}"])

  let #(name, split_by, rest) = splitter.split(sep, line)

  case split_by {
    "}}/{{Weapon|" | "}}/{{Weapon" -> parse_names(rest, [name, ..acc])
    _ -> #([name, ..acc], rest)
  }
}
