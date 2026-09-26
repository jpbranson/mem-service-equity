# Courtesy preview: 311 panel (H8)

Status: **draft, not sent.** Send it two weeks before the 311 panel's
public launch. The launch date is not set: every 311 metric still fails the
publish gate (H10 spec freeze, H3 audit, and reconciliation; see
DECISIONS.md).

Plan 5.6: "each agency receives the panel and methodology two weeks before
public launch. Not for approval; for accuracy. Responses and any changes
made are logged publicly." The log is `courtesy-preview-log.md` in this
folder.

## Before sending

- **Recipient.** The City of Memphis 311 Center and the division that owns
  performance reporting. Copy the council office if the panel shows council
  districts. The right office and contact have not been confirmed; record
  them in DECISIONS.md H8 when they are.
- **What to attach:**
  - the methodology page generated for the launch run;
  - a private preview of the panel (a `--preview` site build, as a zip or a
    private link, never on the public site; see D18);
  - the reconciliation results;
  - the list of open questions below.
- Fill in every `[bracketed]` placeholder and the two dates.

---

## Letter

[Date: at least 14 days before launch]

[Recipient name and title]
City of Memphis, [office]
[Address or email]

**Re: Advance copy of a public 311 service analysis, for accuracy review
before [launch date]**

Dear [name],

I run Memphis Service Equity, a non-commercial, open-source project that
reports how consistently public services are delivered across Memphis
neighborhoods. On [launch date] it will publish a panel based on the City's
public 311 data (the 311 request map service). I'm sending you the panel and
its full methodology two weeks early. You are not being asked to approve it.
I want to find out whether anything in it is inaccurate before the public
sees it.

**What the panel shows.** For each ZIP code, council district and a small
radius around any address:
- how long requests of each type take to close, in business days on the
  City's own holiday calendar;
- how often a closed request is followed by a new request of the same type
  at the same spot;
- how many requests each area makes per 1,000 residents, labelled as demand
  and not as performance.

Each number is shown with its uncertainty and sample size, and small areas
are suppressed. No neighborhood rankings or composite scores are published.

**How it was checked.** [Summarize the reconciliation: which City figures were
reproduced from the same data, and how closely.] [Keep this sentence only once
the H3 audit is committed:] At least 100 records were traced by hand from the
311 map to the published numbers.

**Where we would value the City's input.**
1. **Service targets.** The only official target we found is for potholes
   (5–10 business days, on memphistn.gov). Is there an official service
   level for other request types? We do not use the "3–7 days" and "82%
   on-time" figures that appear on memphisgov.com, because that site is not
   run by the City.
2. **Status and resolution codes.** Which codes mean the work was done, and
   which mean the request was closed without work (for example, private
   property or not the City's responsibility)?
3. **Closing a request.** Does "Closed" always mean the problem was
   addressed? Is there a reopen status we should use?
4. **Request origin.** Can requests filed by City staff be told apart from
   those filed by residents?
5. Anything in the attached methodology that misdescribes how the City
   works.

We'll log every response we receive, and any change we make because of it,
in the project's public methodology notes. If you would prefer your comments
not be attributed to you by name, we'll attribute them to the City.

The full methodology and code are public at [repository URL]. The preview is
at [private link or attachment].

Thank you for your time,

[Full name]
[Email]
[Phone]
