// ============================================================
// FactMeasures — Power Query (M) cleaning
// Source: CMS "Timely and Effective Care – Hospital" (dataset yv7e-xc69)
// Project: Lincoln ED Throughput Benchmark
// Analyst: Alex Jardine
// ------------------------------------------------------------
// Cleans the long-format measures table: splits the mixed
// numeric/categorical Score column into two typed fields,
// flags footnoted (suppressed/low-sample) rows, filters to NE,
// and trims match/key columns. Loads to the Power BI model as
// the fact table (many-side of the relationship to DimHospital).
// ============================================================

let
    Source = Csv.Document(File.Contents("C:\Users\amjar\Downloads\Timely_and_Effective_Care-Hospital.csv"),[Delimiter=",", Columns=16, Encoding=1252, QuoteStyle=QuoteStyle.None]),
    #"Promoted Headers" = Table.PromoteHeaders(Source, [PromoteAllScalars=true]),
    #"Changed Type" = Table.TransformColumnTypes(#"Promoted Headers",{{"Start Date", type date}, {"End Date", type date}}),
    #"Replaced Value" = Table.ReplaceValue(#"Changed Type","Not Available",null,Replacer.ReplaceValue,{"Score"}),
    #"Duplicated Column" = Table.DuplicateColumn(#"Replaced Value", "Score", "Score - Copy"),
    #"Duplicated Column1" = Table.DuplicateColumn(#"Duplicated Column", "Score", "Score - Copy.1"),
    #"Renamed Columns" = Table.RenameColumns(#"Duplicated Column1",{{"Score - Copy", "Score_Numeric"}, {"Score - Copy.1", "Score_Category"}}),
    #"Replaced Value1" = Table.ReplaceValue(#"Renamed Columns","Not Available",null,Replacer.ReplaceValue,{"Score_Numeric"}),
    #"Changed Type1" = Table.TransformColumnTypes(#"Replaced Value1",{{"Score_Numeric", type number}}),
    #"Replaced Errors" = Table.ReplaceErrorValues(#"Changed Type1", {{"Score_Numeric", null}}),
    #"Flag footnoted scores" = Table.AddColumn(#"Replaced Errors", "Score_Category_2", each if List.Contains({"low","medium","high","very high"}, Text.Lower([Score_Category]))
then Text.Lower([Score_Category]) else null),
    #"Removed Columns" = Table.RemoveColumns(#"Flag footnoted scores",{"Score_Category"}),
    #"Renamed Columns1" = Table.RenameColumns(#"Removed Columns",{{"Score_Category_2", "Score_Category"}}),
    #"Filtered Rows" = Table.SelectRows(#"Renamed Columns1", each ([State] = "NE")),
    #"Removed Columns1" = Table.RemoveColumns(#"Filtered Rows",{"Score"}),
    // Flagging any footnote rather than decoding codes — benchmarking only needs clean vs caveated distinction. Extend with List.Contains on footnote codes if a stakeholder needs suppression reasons.
    #"Split score into numeric vs category" = Table.AddColumn(#"Removed Columns1", "Data_Status", each if [Footnote] = null or Text.Trim(Text.From([Footnote])) = ""
then "Reported"
else "Suppressed/Low Sample"),
    // Trim match/key columns only (join key, filter columns, grouping field).
    // Display-only columns (Facility Name) left untrimmed.
    #"Trimmed Text" = Table.TransformColumns(#"Split score into numeric vs category",{{"Facility ID", Text.Trim, type text}, {"Measure ID", Text.Trim, type text}, {"Score_Category", Text.Trim, type text}, {"State", Text.Trim, type text}})
in
    #"Trimmed Text"
