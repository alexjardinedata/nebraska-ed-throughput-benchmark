// ============================================================
// DimHospital — Power Query (M) cleaning
// Source: CMS "Hospital General Information"
// Project: Lincoln ED Throughput Benchmark
// Analyst: Alex Jardine
// ------------------------------------------------------------
// Builds the lean hospital dimension table: filters to NE,
// keeps only model-relevant columns, cleans the star rating,
// trims and de-duplicates the join key, and adds the Org_Group
// classification (Bryan network / Lincoln competitor / other).
// Loads to the Power BI model as the dimension (one-side of the
// relationship to FactMeasures). Carries the real Hospital Type
// column used for the acute / critical-access split.
// ============================================================

let
    Source = Csv.Document(File.Contents("C:\Users\amjar\Downloads\Hospital_General_Information.csv"),[Delimiter=",", Columns=38, Encoding=1252, QuoteStyle=QuoteStyle.None]),
    #"Promoted Headers" = Table.PromoteHeaders(Source, [PromoteAllScalars=true]),
    #"Filtered Rows" = Table.SelectRows(#"Promoted Headers", each ([State] = "NE")),
    // dimension tables should be lean
    #"Keep model columns" = Table.SelectColumns(#"Filtered Rows",{"Facility ID", "Facility Name", "City/Town", "County/Parish", "Hospital Type", "Hospital Ownership", "Emergency Services", "Hospital overall rating"}),
    #"Replaced Value" = Table.ReplaceValue(#"Keep model columns","Not Available",null,Replacer.ReplaceValue,{"Hospital overall rating"}),
    #"Filtered Rows1" = Table.SelectRows(#"Replaced Value", each true),
    // Star rating kept numeric; Not Available --> null rather than zero - zero would poison averages
    #"Clean Star Rating" = Table.TransformColumnTypes(#"Filtered Rows1",{{"Hospital overall rating", Int64.Type}}),
    #"Trimmed Text" = Table.TransformColumns(#"Clean Star Rating",{{"Facility ID", Text.Trim, type text}}),
    // Enforce key uniqueness - required for a 1 side of relationship
    #"Removed Duplicates on the key" = Table.Distinct(#"Trimmed Text", {"Facility ID"}),
    #"Added Custom" = Table.AddColumn(#"Removed Duplicates on the key", "Org_Group", each if List.Contains({"280003","280134","280139","281354","281328"}, [Facility ID]) then "Bryan Health Network"
else if [Facility ID] = "280020" then "Lincoln Competitor"
else "Other Nebraska"),
    // Trim Hospital Type — grouping field for the acute / critical-access split
    #"Trimmed Text1" = Table.TransformColumns(#"Added Custom",{{"Hospital Type", Text.Trim, type text}})
in
    #"Trimmed Text1"
