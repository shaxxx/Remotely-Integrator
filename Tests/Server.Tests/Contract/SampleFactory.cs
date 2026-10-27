using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Reflection;

namespace Remotely.Server.Tests.Contract
{
    /// <summary>
    /// Builds deterministic sample values for the protocol contract (golden file) tests.
    /// The same type and seed always produce the same value, on any runtime version.
    /// </summary>
    /// <remarks>
    /// Rules:
    /// <list type="bullet">
    /// <item>string: "&lt;PropertyName&gt;-&lt;seed&gt;"; a value outside any property (a hub argument or its elements) uses the type name: "String-&lt;seed&gt;".</item>
    /// <item>numbers: seed; bool: true; enum: first declared value that differs from default.</item>
    /// <item>DateTime and DateTimeOffset: 2022-09-16T10:06:00Z; Guid: new Guid(seed, 0, 0, new byte[8]); byte[]: { 1, 2, 3, (byte)seed }.</item>
    /// <item>arrays and lists: 2 elements (element i gets seed + i); dictionaries: 1 element. Collection interfaces become List&lt;T&gt;, IDictionary/IReadOnlyDictionary become Dictionary.</item>
    /// <item>Not in the brief: Nullable&lt;T&gt; gets the T sample; TimeSpan is seed seconds. Any other primitive, object, non-collection interface or abstract class throws NotSupportedException.</item>
    /// <item>classes: public properties with a public setter (init counts as a setter), recursively up to depth 2; deeper composite values are null.</item>
    /// </list>
    /// Depth: the value passed to <see cref="Create"/> is depth 0 and the values of its properties are depth 1.
    /// A collection does not add a level: its elements are at the collection's depth.
    /// A composite value (class, struct, array other than byte[], collection, dictionary) deeper than <see cref="MaxDepth"/> is null (default for structs).
    /// </remarks>
    public static class SampleFactory
    {
        public const int MaxDepth = 2;

        public static readonly DateTime SampleDateTime = new DateTime(2022, 9, 16, 10, 6, 0, DateTimeKind.Utc);

        public static readonly DateTimeOffset SampleDateTimeOffset = new DateTimeOffset(2022, 9, 16, 10, 6, 0, TimeSpan.Zero);

        private const int CollectionLength = 2;

        public static object Create(Type type, int seed = 1)
        {
            if (type is null)
            {
                throw new ArgumentNullException(nameof(type));
            }

            return Build(type, seed, 0, null);
        }

        private static object Build(Type type, int seed, int depth, string name)
        {
            // Nullable<T>: a non-null T sample (boxing a T? with a value yields a boxed T anyway).
            var nullableOf = Nullable.GetUnderlyingType(type);
            if (nullableOf is not null)
            {
                return Build(nullableOf, seed, depth, name);
            }

            if (type == typeof(string))
            {
                return $"{name ?? type.Name}-{seed}";
            }

            if (type == typeof(bool))
            {
                return true;
            }

            if (type.IsEnum)
            {
                return FirstNonDefaultEnumValue(type);
            }

            if (IsNumber(type))
            {
                return Convert.ChangeType(seed, type, CultureInfo.InvariantCulture);
            }

            if (type == typeof(DateTime))
            {
                return SampleDateTime;
            }

            if (type == typeof(DateTimeOffset))
            {
                return SampleDateTimeOffset;
            }

            if (type == typeof(TimeSpan))
            {
                // Not covered by the brief: seed seconds.
                return TimeSpan.FromSeconds(seed);
            }

            if (type == typeof(Guid))
            {
                return new Guid(seed, 0, 0, new byte[8]);
            }

            if (type == typeof(byte[]))
            {
                return new byte[] { 1, 2, 3, (byte)seed };
            }

            if (type.IsPrimitive || type == typeof(object))
            {
                // char, IntPtr, object, ...: no rule yet; add one explicitly rather than produce an accidental value.
                throw new NotSupportedException($"SampleFactory has no rule for {type.FullName}.");
            }

            if (depth > MaxDepth)
            {
                return type.IsValueType ? Activator.CreateInstance(type) : null;
            }

            if (type.IsArray)
            {
                return BuildArray(type, seed, depth, name);
            }

            var dictionaryTypes = FindGenericInterface(type, typeof(IDictionary<,>), typeof(IReadOnlyDictionary<,>));
            if (dictionaryTypes is not null)
            {
                return BuildDictionary(type, dictionaryTypes, seed, depth, name);
            }

            var elementType = FindGenericInterface(type, typeof(ICollection<>), typeof(IEnumerable<>))?[0];
            if (elementType is not null)
            {
                return BuildCollection(type, elementType, seed, depth, name);
            }

            if (type.IsInterface || type.IsAbstract)
            {
                throw new NotSupportedException($"SampleFactory cannot create an instance of {type.FullName}.");
            }

            return BuildObject(type, seed, depth);
        }

        private static bool IsNumber(Type type)
        {
            return type == typeof(byte) || type == typeof(sbyte) ||
                type == typeof(short) || type == typeof(ushort) ||
                type == typeof(int) || type == typeof(uint) ||
                type == typeof(long) || type == typeof(ulong) ||
                type == typeof(float) || type == typeof(double) ||
                type == typeof(decimal);
        }

        private static object FirstNonDefaultEnumValue(Type enumType)
        {
            var defaultValue = Activator.CreateInstance(enumType);

            // Declaration order (metadata order), not Enum.GetValues, which sorts by value.
            var values = enumType
                .GetFields(BindingFlags.Public | BindingFlags.Static)
                .OrderBy(f => f.MetadataToken)
                .Select(f => f.GetValue(null));

            // An enum that only declares its default value gets the default value.
            return values.FirstOrDefault(v => !v.Equals(defaultValue)) ?? defaultValue;
        }

        private static Type[] FindGenericInterface(Type type, params Type[] genericDefinitions)
        {
            foreach (var definition in genericDefinitions)
            {
                if (type.IsGenericType && type.GetGenericTypeDefinition() == definition)
                {
                    return type.GetGenericArguments();
                }

                var match = type.GetInterfaces()
                    .Where(i => i.IsGenericType && i.GetGenericTypeDefinition() == definition)
                    .OrderBy(i => i.FullName, StringComparer.Ordinal)
                    .FirstOrDefault();

                if (match is not null)
                {
                    return match.GetGenericArguments();
                }
            }

            return null;
        }

        private static Array BuildArray(Type type, int seed, int depth, string name)
        {
            if (type.GetArrayRank() != 1)
            {
                throw new NotSupportedException($"SampleFactory supports only single-dimension arrays, not {type.FullName}.");
            }

            var elementType = type.GetElementType();
            var array = Array.CreateInstance(elementType, CollectionLength);
            for (var i = 0; i < CollectionLength; i++)
            {
                array.SetValue(Build(elementType, seed + i, depth, name), i);
            }
            return array;
        }

        private static object BuildCollection(Type type, Type elementType, int seed, int depth, string name)
        {
            var elements = Enumerable.Range(0, CollectionLength)
                .Select(i => Build(elementType, seed + i, depth, name))
                .ToArray();

            // Collection interfaces (IEnumerable<T>, ICollection<T>, IList<T>, IReadOnlyList<T>, ...) become List<T>.
            var concreteType = type.IsInterface ? typeof(List<>).MakeGenericType(elementType) : type;
            if (!type.IsAssignableFrom(concreteType))
            {
                throw new NotSupportedException($"SampleFactory has no concrete collection for {type.FullName}.");
            }

            var collection = Activator.CreateInstance(concreteType);
            var add = typeof(ICollection<>).MakeGenericType(elementType).GetMethod(nameof(ICollection<object>.Add));
            if (!add.DeclaringType.IsAssignableFrom(concreteType))
            {
                throw new NotSupportedException($"SampleFactory cannot add elements to {type.FullName}.");
            }

            foreach (var element in elements)
            {
                add.Invoke(collection, new[] { element });
            }
            return collection;
        }

        private static object BuildDictionary(Type type, Type[] keyValueTypes, int seed, int depth, string name)
        {
            var concreteType = type.IsInterface
                ? typeof(Dictionary<,>).MakeGenericType(keyValueTypes)
                : type;

            var dictionary = Activator.CreateInstance(concreteType);
            var add = typeof(IDictionary<,>).MakeGenericType(keyValueTypes).GetMethod(nameof(IDictionary<object, object>.Add));
            if (!add.DeclaringType.IsAssignableFrom(concreteType))
            {
                throw new NotSupportedException($"SampleFactory cannot add entries to {type.FullName}.");
            }

            add.Invoke(dictionary, new[]
            {
                Build(keyValueTypes[0], seed, depth, name),
                Build(keyValueTypes[1], seed, depth, name)
            });
            return dictionary;
        }

        private static object BuildObject(Type type, int seed, int depth)
        {
            var properties = type
                .GetProperties(BindingFlags.Public | BindingFlags.Instance)
                .Where(p => p.GetIndexParameters().Length == 0)
                .OrderBy(p => p.Name, StringComparer.Ordinal)
                .ToArray();

            var instance = CreateInstance(type, properties, seed, depth);

            foreach (var property in properties.Where(p => p.SetMethod?.IsPublic == true))
            {
                property.SetValue(instance, Build(property.PropertyType, seed, depth + 1, property.Name));
            }

            return instance;
        }

        private static object CreateInstance(Type type, PropertyInfo[] properties, int seed, int depth)
        {
            if (type.IsValueType || type.GetConstructor(Type.EmptyTypes) is not null)
            {
                return Activator.CreateInstance(type);
            }

            // No parameterless constructor (e.g. ClipboardTextDto): use the public constructor with the most
            // parameters. Each argument is built like the property of the same name (case-insensitive),
            // so getter-only properties set by the constructor get the same values as settable ones.
            var constructor = type.GetConstructors()
                .OrderByDescending(c => c.GetParameters().Length)
                .ThenBy(c => string.Join(",", c.GetParameters().Select(p => p.ParameterType.FullName)), StringComparer.Ordinal)
                .FirstOrDefault();

            if (constructor is null)
            {
                throw new NotSupportedException($"SampleFactory found no public constructor on {type.FullName}.");
            }

            var arguments = constructor.GetParameters()
                .Select(parameter =>
                {
                    var property = properties.FirstOrDefault(p => string.Equals(p.Name, parameter.Name, StringComparison.OrdinalIgnoreCase));
                    return Build(parameter.ParameterType, seed, depth + 1, property?.Name ?? parameter.Name);
                })
                .ToArray();

            return constructor.Invoke(arguments);
        }
    }
}
