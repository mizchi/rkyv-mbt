///|
pub struct TelemetryView {
  reader : @rkyv.Reader
  offset : Int
}

///|
pub fn TelemetryView::at(
  reader : @rkyv.Reader,
  offset : Int,
) -> TelemetryView raise @rkyv.RkyvError {
  reader.validate_range(offset, 40)
  { reader, offset }
}

///|
pub fn TelemetryView::root(
  bytes : Bytes,
) -> TelemetryView raise @rkyv.RkyvError {
  let reader = @rkyv.Reader::new(bytes)
  let offset = reader.root_offset(40)
  TelemetryView::at(reader, offset)
}

///|
pub fn TelemetryView::validate(
  bytes : Bytes,
) -> TelemetryView raise @rkyv.RkyvError {
  let view = TelemetryView::root(bytes)
  view.validate_all(256)
  view
}

///|
pub fn TelemetryView::validate_all(
  self : TelemetryView,
  remaining_depth : Int,
) -> Unit raise @rkyv.RkyvError {
  @rkyv.require_validation_depth(remaining_depth)
  let header = self.reader.read_vec_header_with_element_size(self.offset, 2)
  for index in 0..<header.length {
    let _ = self.reader.read_i16(header.data_offset + index * 2)
  }
  let header = self.reader.read_vec_header_with_element_size(self.offset + 8, 8)
  for index in 0..<header.length {
    let _ = self.reader.read_f64(header.data_offset + index * 8)
  }
  match self.reader.read_option_value_offset_strict(self.offset + 16, 4) {
    None => ()
    Some(value_offset) => {
      let header = self.reader.read_vec_header_with_element_size(value_offset, 8)
      for index in 0..<header.length {
        let _ = self.reader.read_string(header.data_offset + index * 8)
      }
    }
  }
  match self.reader.read_option_value_offset_strict(self.offset + 28, 4) {
    None => ()
    Some(value_offset) => {
      let header = self.reader.read_vec_header_with_element_size(value_offset, 2)
      for index in 0..<header.length {
        let _ = self.reader.read_i16(header.data_offset + index * 2)
      }
    }
  }
}

///|
pub fn TelemetryView::samples(
  self : TelemetryView,
) -> TelemetrySamplesView raise @rkyv.RkyvError {
  let header = self.reader.read_vec_header_with_element_size(self.offset, 2)
  {
    reader: self.reader,
    data_offset: header.data_offset,
    length: header.length,
  }
}

///|
pub struct TelemetrySamplesView {
  reader : @rkyv.Reader
  data_offset : Int
  length : Int
}

///|
pub fn TelemetrySamplesView::length(self : TelemetrySamplesView) -> Int {
  self.length
}

///|
pub fn TelemetrySamplesView::at(
  self : TelemetrySamplesView,
  index : Int,
) -> Int? raise @rkyv.RkyvError {
  if index < 0 || index >= self.length {
    None
  } else {
    Some(self.reader.read_i16(self.data_offset + index * 2))
  }
}

///|
pub fn TelemetryView::ratios(
  self : TelemetryView,
) -> TelemetryRatiosView raise @rkyv.RkyvError {
  let header = self.reader.read_vec_header_with_element_size(self.offset + 8, 8)
  {
    reader: self.reader,
    data_offset: header.data_offset,
    length: header.length,
  }
}

///|
pub struct TelemetryRatiosView {
  reader : @rkyv.Reader
  data_offset : Int
  length : Int
}

///|
pub fn TelemetryRatiosView::length(self : TelemetryRatiosView) -> Int {
  self.length
}

///|
pub fn TelemetryRatiosView::at(
  self : TelemetryRatiosView,
  index : Int,
) -> Double? raise @rkyv.RkyvError {
  if index < 0 || index >= self.length {
    None
  } else {
    Some(self.reader.read_f64(self.data_offset + index * 8))
  }
}

///|
pub fn TelemetryView::labels(
  self : TelemetryView,
) -> TelemetryLabelsView? raise @rkyv.RkyvError {
  match self.reader.read_option_value_offset(self.offset + 16, 4) {
    None => None
    Some(value_offset) => {
      let header = self.reader.read_vec_header_with_element_size(
        value_offset,
        8,
      )
      Some({
        reader: self.reader,
        data_offset: header.data_offset,
        length: header.length,
      })
    }
  }
}

///|
pub struct TelemetryLabelsView {
  reader : @rkyv.Reader
  data_offset : Int
  length : Int
}

///|
pub fn TelemetryLabelsView::length(self : TelemetryLabelsView) -> Int {
  self.length
}

///|
pub fn TelemetryLabelsView::at(
  self : TelemetryLabelsView,
  index : Int,
) -> String? raise @rkyv.RkyvError {
  if index < 0 || index >= self.length {
    None
  } else {
    Some(self.reader.read_string(self.data_offset + index * 8))
  }
}

///|
pub fn TelemetryView::maybe_samples(
  self : TelemetryView,
) -> TelemetryMaybeSamplesView? raise @rkyv.RkyvError {
  match self.reader.read_option_value_offset(self.offset + 28, 4) {
    None => None
    Some(value_offset) => {
      let header = self.reader.read_vec_header_with_element_size(
        value_offset,
        2,
      )
      Some({
        reader: self.reader,
        data_offset: header.data_offset,
        length: header.length,
      })
    }
  }
}

///|
pub struct TelemetryMaybeSamplesView {
  reader : @rkyv.Reader
  data_offset : Int
  length : Int
}

///|
pub fn TelemetryMaybeSamplesView::length(self : TelemetryMaybeSamplesView) -> Int {
  self.length
}

///|
pub fn TelemetryMaybeSamplesView::at(
  self : TelemetryMaybeSamplesView,
  index : Int,
) -> Int? raise @rkyv.RkyvError {
  if index < 0 || index >= self.length {
    None
  } else {
    Some(self.reader.read_i16(self.data_offset + index * 2))
  }
}

///|
pub struct TelemetryInput {
  samples : Array[Int]
  ratios : Array[Double]
  labels : Array[String]?
  maybe_samples : Array[Int]?
}

///|
pub fn TelemetryInput::new(
  samples : Array[Int],
  ratios : Array[Double],
  labels : Array[String]?,
  maybe_samples : Array[Int]?,
) -> TelemetryInput {
  { samples, ratios, labels, maybe_samples }
}

///|
pub fn TelemetryInput::schema() -> @rkyv.Schema {
  @rkyv.Schema::StructLayout(
    [
      { name: "samples", schema: @rkyv.Schema::Vec(@rkyv.Schema::I16) },
      { name: "ratios", schema: @rkyv.Schema::Vec(@rkyv.Schema::F64) },
      { name: "labels", schema: @rkyv.Schema::Option(@rkyv.Schema::Vec(@rkyv.Schema::String)) },
      { name: "maybe_samples", schema: @rkyv.Schema::Option(@rkyv.Schema::Vec(@rkyv.Schema::I16)) },
    ],
    [0, 8, 16, 28],
    40,
  )
}

///|
pub fn TelemetryInput::to_value(self : TelemetryInput) -> @rkyv.Value {
  let samples_value_items : Array[@rkyv.Value] = []
  for value in self.samples {
    samples_value_items.push(@rkyv.Value::I16(value))
  }
  let samples_value = @rkyv.Value::Vec(samples_value_items)
  let ratios_value_items : Array[@rkyv.Value] = []
  for value in self.ratios {
    ratios_value_items.push(@rkyv.Value::F64(value))
  }
  let ratios_value = @rkyv.Value::Vec(ratios_value_items)
  let labels_value = match self.labels {
    None => @rkyv.Value::Option(None)
    Some(value) => {
      let labels_value_some_items : Array[@rkyv.Value] = []
      for value in value {
        labels_value_some_items.push(@rkyv.Value::String(value))
      }
      let labels_value_some = @rkyv.Value::Vec(labels_value_some_items)
      @rkyv.Value::Option(Some(labels_value_some))
    }
  }
  let maybe_samples_value = match self.maybe_samples {
    None => @rkyv.Value::Option(None)
    Some(value) => {
      let maybe_samples_value_some_items : Array[@rkyv.Value] = []
      for value in value {
        maybe_samples_value_some_items.push(@rkyv.Value::I16(value))
      }
      let maybe_samples_value_some = @rkyv.Value::Vec(maybe_samples_value_some_items)
      @rkyv.Value::Option(Some(maybe_samples_value_some))
    }
  }
  @rkyv.Value::Struct([
    { name: "samples", value: samples_value },
    { name: "ratios", value: ratios_value },
    { name: "labels", value: labels_value },
    { name: "maybe_samples", value: maybe_samples_value },
  ])
}

///|
pub fn TelemetryInput::encode(
  self : TelemetryInput,
) -> Bytes raise @rkyv.SchemaError {
  TelemetryInput::schema().encode(self.to_value())
}
