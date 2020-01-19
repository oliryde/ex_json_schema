defmodule ExJsonSchema.Validator.Properties do
  @moduledoc """
  `ExJsonSchema.Validator` implementation for `"properties"` attributes.

  See:

  """

  alias ExJsonSchema.Schema.Root
  alias ExJsonSchema.Validator
  alias ExJsonSchema.Validator.Error

  @behaviour ExJsonSchema.Validator

  @impl ExJsonSchema.Validator
  @spec validate(
          root :: Root.t(),
          schema :: ExJsonSchema.data(),
          property :: {String.t(), ExJsonSchema.data()},
          data :: ExJsonSchema.data()
        ) :: Validator.errors() | no_return
  def validate(root, schema, {"properties", _}, properties = %{}) do
    do_validate(root, schema, properties)
  end

  def validate(_, _, _, _) do
    []
  end

  defp do_validate(root, schema, properties) do
    validated_known_properties = validate_known_properties(root, schema, properties)

    validation_errors(validated_known_properties) ++
      validate_additional_properties(
        root,
        schema["additionalProperties"],
        unvalidated_properties(properties, validated_known_properties)
      )
  end

  defp validate_known_properties(root, schema, properties) do
    validate_named_properties(root, schema["properties"], properties) ++
      validate_pattern_properties(root, schema["patternProperties"], properties)
  end

  defp validate_named_properties(root, schema, properties) do
    schema
    |> Enum.filter(&Map.has_key?(properties, elem(&1, 0)))
    |> Enum.map(fn
      {name, true} ->
        {name, []}

      {name, false} ->
        {name, [%Error{error: %{message: "Schema does not allow property #{name}"}, path: ""}]}

      {name, property_schema} ->
        {name, Validator.validation_errors(root, property_schema, properties[name], "/#{name}")}
    end)
  end

  defp validate_pattern_properties(_, nil, _), do: []

  defp validate_pattern_properties(root, schema, properties) do
    Enum.flat_map(schema, &validate_pattern_property(root, &1, properties))
  end

  defp validate_pattern_property(_root, {pattern, true}, properties) do
    properties
    |> properties_matching(pattern)
    |> Enum.map(fn {name, _property} -> {name, []} end)
  end

  defp validate_pattern_property(_root, {pattern, false}, properties) do
    properties
    |> properties_matching(pattern)
    |> Enum.map(fn {name, _property} ->
      {name,
       [
         %Error{
           error: %{message: "Schema does not allow property names matching #{pattern}"},
           path: ""
         }
       ]}
    end)
  end

  defp validate_pattern_property(root, {pattern, schema}, properties) do
    properties_matching(properties, pattern)
    |> Enum.map(fn {name, property} ->
      {name, Validator.validation_errors(root, schema, property, "/#{name}")}
    end)
  end

  defp validate_additional_properties(root, schema, properties) when is_map(schema) do
    Enum.flat_map(properties, fn {name, property} ->
      Validator.validation_errors(root, schema, property, "/#{name}")
    end)
  end

  defp validate_additional_properties(_, false, properties) when map_size(properties) > 0 do
    Enum.map(properties, fn {name, _} ->
      %Error{error: %Error.AdditionalProperties{}, path: "/#{name}"}
    end)
  end

  defp validate_additional_properties(_, _, _), do: []

  defp validation_errors(validated_properties) do
    validated_properties |> Keyword.values() |> List.flatten()
  end

  defp properties_matching(properties, pattern) do
    regex = Regex.compile!(pattern)
    Enum.filter(properties, &Regex.match?(regex, elem(&1, 0)))
  end

  defp unvalidated_properties(properties, validated_properties) do
    keys =
      properties
      |> keys_as_set()
      |> MapSet.difference(keys_as_set(validated_properties))
      |> Enum.to_list()

    Map.take(properties, keys)
  end

  defp keys_as_set(properties) do
    properties |> Enum.map(&elem(&1, 0)) |> Enum.into(MapSet.new())
  end
end
