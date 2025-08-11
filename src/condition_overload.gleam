import argv
import gleam/fetch
import gleam/http/request
import gleam/int
import gleam/io
import gleam/javascript/promise
import gleam/list
import gleam/pair
import gleam/result
import gleam/string
import splitter

pub fn main() {
  let search =
    argv.load().arguments
    |> list.reduce(fn(acc, x) { acc <> " " <> x })
    |> result.map(string.lowercase)
  case search {
    Error(_) -> io.println("Please provide a search term")
    Ok(search) -> {
      do_search(search)
    }
  }
}

// do search and print result if any
//
fn do_search(search: String) {
  [
    "https://wiki.warframe.com/w/Condition_Overload_%28Mechanic%29?action=edit&section=7",
    "https://wiki.warframe.com/w/Condition_Overload_%28Mechanic%29?action=edit&section=8",
  ]
  |> list.map(get_gun_page_data)
  |> promise.await_list()
  |> promise.map(result.values)
  |> promise.map(list.flatten)
  |> promise.map(
    list.filter(_, fn(item) {
      item.names
      |> list.any(fn(name) {
        let lower = string.lowercase(name)
        string.contains(lower, search)
      })
    }),
  )
  |> promise.map(fn(rows) {
    case list.length(rows) {
      0 -> io.println("\"" <> search <> "\" could not be found")
      _ -> {
        rows
        |> list.take(4)
        |> list.map(format_row)
        |> list.reduce(fn(acc, x) { acc <> " || " <> x })
        |> result.map(io.println)
        |> result.unwrap_both()
      }
    }
  })
  Nil
}

// format row into human readable string
//
fn format_row(row: Row) -> String {
  let rating = case row {
    Row(math_behavior: "Multiplying", ..) -> "very good"
    Row(math_behavior: "Adding", co_bonus_rel_base:, ..) -> {
      let co_bonus_rel_base =
        co_bonus_rel_base
        |> string.split_once("%")
        |> result.map(pair.first)
        |> result.try(int.parse)
        |> result.unwrap(0)

      case co_bonus_rel_base {
        bonus if bonus > 100 -> "good"
        bonus if bonus == 100 -> "normal"
        bonus if bonus < 100 -> "poor"
        _ -> panic as "unreachable(some secret fourth option)"
      }
    }

    Row(math_behavior: "N/A", ..) | Row(math_behavior: "", ..) -> "bad"

    _ -> "some secret third option"
  }

  let Row(
    names:,
    attack:,
    projectile:,
    base_damage: _,
    co_bonus_at_100: _,
    co_bonus_rel_base: _,
    math_behavior: _,
    notes: _,
  ) = row

  let name =
    list.reduce(names, fn(acc, x) { acc <> " / " <> x })
    |> result.unwrap("")

  "The '"
  <> name
  <> "' '"
  <> attack
  <> " "
  <> projectile
  <> "' has a "
  <> rating
  <> " interaction with GunCO."
}

// do request and return Row if successful
// 
fn get_gun_page_data(
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
    co_bonus_rel_base: String,
    math_behavior: String,
    notes: String,
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
// as well as both mixed, into row type
// 
//
fn process_lines(lines: List(String), acc: List(Row)) -> List(Row) {
  case lines {
    ["|{{Weapon|" <> name_line, ..rest] -> {
      let #(row, rest) = parse_row(name_line, rest)

      process_lines(rest, [row, ..acc])
    }
    [_, ..rest] -> process_lines(rest, acc)
    [] -> acc
  }
}

// parses 1 'Row' type worth of data from the supplied lines
// handles single line, multi line and mixed data
//
fn parse_row(name_line: String, lines: List(String)) -> #(Row, List(String)) {
  let #(names, line_rest) = parse_names(name_line, [])

  let #(attack, line_rest, rest) = parse_next_value(line_rest, lines)
  let #(projectile, line_rest, rest) = parse_next_value(line_rest, rest)
  let #(base_damage, line_rest, rest) = parse_next_value(line_rest, rest)
  let #(co_bonus_at_100, line_rest, rest) = parse_next_value(line_rest, rest)
  let #(co_bonus_rel_base, line_rest, rest) = parse_next_value(line_rest, rest)
  let #(math_behavior, line_rest, rest) = parse_next_value(line_rest, rest)
  let #(notes, _, rest) = parse_next_value(line_rest, rest)

  #(
    Row(
      names:,
      attack:,
      projectile:,
      base_damage:,
      co_bonus_at_100:,
      co_bonus_rel_base:,
      math_behavior:,
      notes:,
    ),
    rest,
  )
}

// parses the next value from the data
// 
fn parse_next_value(
  line_rest: String,
  lines: List(String),
) -> #(String, String, List(String)) {
  let sep = splitter.new(["||"])

  case splitter.split(sep, line_rest) {
    #("", _, _) -> handle_empty_line(sep, lines)
    #(value, "||", line_rest) -> #(value, line_rest, lines)
    #(value, "", _) -> #(value, "", lines)
    #(_, _, _) -> handle_empty_line(sep, lines)
  }
}

// 
//
fn handle_empty_line(sep, lines) {
  case lines {
    ["|-", ..] -> #("", "", lines)
    ["|" <> value, ..rest] -> {
      case splitter.split(sep, value) {
        #(value, "||", line_rest) -> #(value, line_rest, rest)
        #(value, _, _) -> #(value, "", rest)
      }
    }
    [] | [_] | [_, _, ..] -> #("", "", lines)
  }
}

// parse the weapon names 
//
fn parse_names(line: String, acc) {
  let sep = splitter.new(["}}/{{Weapon|", "}}"])

  let #(name, split_by, rest) = splitter.split(sep, line)

  let name =
    string.split_once(name, "|")
    |> result.map(pair.first)
    |> result.unwrap(name)

  case split_by {
    "}}/{{Weapon|" | "}}/{{Weapon" -> parse_names(rest, [name, ..acc])
    _ -> {
      // handle special cases where extra text is included after the weapon names
      let rest =
        string.split_once(rest, "||")
        |> result.map(pair.second)
        |> result.unwrap(rest)

      #([name, ..acc], rest)
    }
  }
}
