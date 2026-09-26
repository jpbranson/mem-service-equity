# Independent reviewer (H7)

Status: **draft, not sent.** No reviewer has been approached yet.

Plan 5.6 says that before launch, at least one person who did not build the
pipeline reads the specs and tries to break the numbers. Ideally that is
someone from the relevant agency or a local academic. Plan 13 and 11 name
three kinds of candidate:
- **Data Midsouth / Innovate Memphis.** It runs the regional open-data hub
  and is the plan's preferred institutional partner.
- **A University of Memphis faculty member** with survey, public
  administration, urban planning or biostatistics experience.
- **A former City of Memphis or agency analyst** who knows how 311 records
  are kept.

The 311 panel launches first, so the first review covers 311. Other panels
can use the same reviewer or a different one.

## What the reviewer is asked to do (311)

About 4–6 hours:
1. Read the five specs in `specs/311/`. Each spec has three adversarial
   objections with answers. Add better objections, or say where an answer
   is weak.
2. Look at a preview build of the site and try to break it. A `--preview`
   build shows every number with its publication status. Unpublished
   numbers never go on the public site (D18), so send the preview privately,
   for example as a zip of `site/` to serve locally with
   `python -m http.server`.
   - Find an area or request type where a number looks wrong.
   - Check that small areas are suppressed.
   - Check that the intervals are shown.
   - Check that no view ranks neighborhoods.
3. Spot-check one number end to end using the review packets:
   - `docs/reviews/h20-golden/` has worksheets that list each record behind
     a published value.
   - The H3 audit sheet is the same kind of trace, on a random sample.
4. Write down what they found, in any form. Findings, and what the project
   changed in response, are logged publicly.

The reviewer does not approve anything and is not responsible for the
numbers. If they want, they are credited on the methodology page. If they
prefer, they can review anonymously; the log then says "an independent
reviewer".

## Email draft

> **Subject:** Would you try to break our 311 numbers? (Memphis Service Equity)
>
> Hello [name],
>
> I'm building Memphis Service Equity, a non-commercial open-source project
> that measures whether city services work the same across Memphis
> neighborhoods. The first panel covers 311: how long requests take to
> close, how often problems come back after a request is closed, and how
> many requests each area makes per 1,000 residents. Every number is shown
> with its sample size and uncertainty. Numbers too small to be reliable are
> suppressed, and nothing is ranked.
>
> Before anything goes public, the project's rules require someone who did
> not build it to read the metric definitions and try to break the numbers.
> I'd be grateful if you would be that person for the 311 panel. It should
> take about 4–6 hours. You would get the definitions, a preview of the site,
> and worksheets for tracing numbers back to individual requests. You don't
> approve anything. You tell me what's wrong, and what I change in response
> is logged publicly.
>
> Everything is in the open: [repository URL]. The methodology is at
> [site URL]/methodology.html.
>
> Would you be willing, or can you suggest someone who might be?
>
> Thank you,
> [name]
> [contact]

## Log

| Date | Who (or "anonymous") | Outcome |
|---|---|---|
| | | |

Once a reviewer has finished the 311 review, mark H7 done in DECISIONS.md.
