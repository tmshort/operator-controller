package variablesources_test

import (
	"context"
	"fmt"

	. "github.com/onsi/ginkgo/v2"
	. "github.com/onsi/gomega"

	"github.com/operator-framework/deppy/pkg/deppy"
	"github.com/operator-framework/deppy/pkg/deppy/input"
	"github.com/operator-framework/operator-registry/alpha/property"

	olmentity "github.com/operator-framework/operator-controller/internal/resolution/entities"
	olmvariables "github.com/operator-framework/operator-controller/internal/resolution/variables"
	"github.com/operator-framework/operator-controller/internal/resolution/variablesources"
)

var bundleSet = map[deppy.Identifier]*input.Entity{
	// required package bundles
	"bundle-1": input.NewEntity("bundle-1", map[string]string{
		property.TypePackage:     `{"packageName": "test-package", "version": "1.0.0"}`,
		property.TypeChannel:     `{"channelName":"stable","priority":0}`,
		property.TypeGVKRequired: `[{"group":"foo.io","kind":"Foo","version":"v1"}]`,
		property.TypeGVK:         `[{"group":"bit.io","kind":"Bit","version":"v1"}]`,
	}),
	"bundle-2": input.NewEntity("bundle-2", map[string]string{
		property.TypePackage:         `{"packageName": "test-package", "version": "2.0.0"}`,
		property.TypeChannel:         `{"channelName":"stable","priority":0}`,
		property.TypeGVKRequired:     `[{"group":"foo.io","kind":"Foo","version":"v1"}]`,
		property.TypePackageRequired: `[{"packageName": "some-package", "versionRange": ">=1.0.0 <2.0.0"}]`,
		property.TypeGVK:             `[{"group":"bit.io","kind":"Bit","version":"v1"}]`,
	}),

	// dependencies
	"bundle-3": input.NewEntity("bundle-3", map[string]string{
		property.TypePackage: `{"packageName": "some-package", "version": "1.0.0"}`,
		property.TypeChannel: `{"channelName":"stable","priority":0}`,
		property.TypeGVK:     `[{"group":"fiz.io","kind":"Fiz","version":"v1"}]`,
	}),
	"bundle-4": input.NewEntity("bundle-4", map[string]string{
		property.TypePackage: `{"packageName": "some-package", "version": "1.5.0"}`,
		property.TypeChannel: `{"channelName":"stable","priority":0}`,
		property.TypeGVK:     `[{"group":"fiz.io","kind":"Fiz","version":"v1"}]`,
	}),
	"bundle-5": input.NewEntity("bundle-5", map[string]string{
		property.TypePackage: `{"packageName": "some-package", "version": "2.0.0"}`,
		property.TypeChannel: `{"channelName":"stable","priority":0}`,
		property.TypeGVK:     `[{"group":"fiz.io","kind":"Fiz","version":"v1"}]`,
	}),
	"bundle-6": input.NewEntity("bundle-6", map[string]string{
		property.TypePackage: `{"packageName": "some-other-package", "version": "1.0.0"}`,
		property.TypeChannel: `{"channelName":"stable","priority":0}`,
		property.TypeGVK:     `[{"group":"foo.io","kind":"Foo","version":"v1"}]`,
	}),
	"bundle-7": input.NewEntity("bundle-7", map[string]string{
		property.TypePackage:         `{"packageName": "some-other-package", "version": "1.5.0"}`,
		property.TypeChannel:         `{"channelName":"stable","priority":0}`,
		property.TypeGVK:             `[{"group":"foo.io","kind":"Foo","version":"v1"}]`,
		property.TypeGVKRequired:     `[{"group":"bar.io","kind":"Bar","version":"v1"}]`,
		property.TypePackageRequired: `[{"packageName": "another-package", "versionRange": "< 2.0.0"}]`,
	}),

	// dependencies of dependencies
	"bundle-8": input.NewEntity("bundle-8", map[string]string{
		property.TypePackage: `{"packageName": "another-package", "version": "1.0.0"}`,
		property.TypeChannel: `{"channelName":"stable","priority":0}`,
		property.TypeGVK:     `[{"group":"foo.io","kind":"Foo","version":"v1"}]`,
	}),
	"bundle-9": input.NewEntity("bundle-9", map[string]string{
		property.TypePackage: `{"packageName": "bar-package", "version": "1.0.0"}`,
		property.TypeChannel: `{"channelName":"stable","priority":0}`,
		property.TypeGVK:     `[{"group":"bar.io","kind":"Bar","version":"v1"}]`,
	}),
	"bundle-10": input.NewEntity("bundle-10", map[string]string{
		property.TypePackage: `{"packageName": "bar-package", "version": "2.0.0"}`,
		property.TypeChannel: `{"channelName":"stable","priority":0}`,
		property.TypeGVK:     `[{"group":"bar.io","kind":"Bar","version":"v1"}]`,
	}),

	// test-package-2 required package - no dependencies
	"bundle-14": input.NewEntity("bundle-14", map[string]string{
		property.TypePackage: `{"packageName": "test-package-2", "version": "1.5.0"}`,
		property.TypeChannel: `{"channelName":"stable","priority":0}`,
		property.TypeGVK:     `[{"group":"buz.io","kind":"Buz","version":"v1"}]`,
	}),
	"bundle-15": input.NewEntity("bundle-15", map[string]string{
		property.TypePackage: `{"packageName": "test-package-2", "version": "2.0.1"}`,
		property.TypeChannel: `{"channelName":"stable","priority":0}`,
		property.TypeGVK:     `[{"group":"buz.io","kind":"Buz","version":"v1"}]`,
	}),
	"bundle-16": input.NewEntity("bundle-16", map[string]string{
		property.TypePackage: `{"packageName": "test-package-2", "version": "3.16.0"}`,
		property.TypeChannel: `{"channelName":"stable","priority":0}`,
		property.TypeGVK:     `[{"group":"buz.io","kind":"Buz","version":"v1"}]`,
	}),

	// completely unrelated
	"bundle-11": input.NewEntity("bundle-11", map[string]string{
		property.TypePackage: `{"packageName": "unrelated-package", "version": "2.0.0"}`,
		property.TypeChannel: `{"channelName":"stable","priority":0}`,
		property.TypeGVK:     `[{"group":"buz.io","kind":"Buz","version":"v1alpha1"}]`,
	}),
	"bundle-12": input.NewEntity("bundle-12", map[string]string{
		property.TypePackage: `{"packageName": "unrelated-package-2", "version": "2.0.0"}`,
		property.TypeChannel: `{"channelName":"stable","priority":0}`,
		property.TypeGVK:     `[{"group":"buz.io","kind":"Buz","version":"v1alpha1"}]`,
	}),
	"bundle-13": input.NewEntity("bundle-13", map[string]string{
		property.TypePackage: `{"packageName": "unrelated-package-2", "version": "3.0.0"}`,
		property.TypeChannel: `{"channelName":"stable","priority":0}`,
		property.TypeGVK:     `[{"group":"buz.io","kind":"Buz","version":"v1alpha1"}]`,
	}),
}

var _ = Describe("CRDUniquenessConstraintsVariableSource", func() {
	var (
		inputVariableSource         *MockInputVariableSource
		crdConstraintVariableSource *variablesources.CRDUniquenessConstraintsVariableSource
		ctx                         context.Context
		entitySource                input.EntitySource
	)

	BeforeEach(func() {
		inputVariableSource = &MockInputVariableSource{}
		crdConstraintVariableSource = variablesources.NewCRDUniquenessConstraintsVariableSource(inputVariableSource)
		ctx = context.Background()

		// the entity is not used in this variable source
		entitySource = &PanicEntitySource{}
	})

	It("should get variables from the input variable source and create global constraint variables", func() {
		inputVariableSource.ResultSet = []deppy.Variable{
			olmvariables.NewRequiredPackageVariable("test-package", []*olmentity.BundleEntity{
				olmentity.NewBundleEntity(bundleSet["bundle-2"]),
				olmentity.NewBundleEntity(bundleSet["bundle-1"]),
			}),
			olmvariables.NewRequiredPackageVariable("test-package-2", []*olmentity.BundleEntity{
				olmentity.NewBundleEntity(bundleSet["bundle-14"]),
				olmentity.NewBundleEntity(bundleSet["bundle-15"]),
				olmentity.NewBundleEntity(bundleSet["bundle-16"]),
			}),
			olmvariables.NewBundleVariable(
				olmentity.NewBundleEntity(bundleSet["bundle-2"]),
				[]*olmentity.BundleEntity{
					olmentity.NewBundleEntity(bundleSet["bundle-3"]),
					olmentity.NewBundleEntity(bundleSet["bundle-4"]),
					olmentity.NewBundleEntity(bundleSet["bundle-5"]),
					olmentity.NewBundleEntity(bundleSet["bundle-6"]),
					olmentity.NewBundleEntity(bundleSet["bundle-7"]),
				},
			),
			olmvariables.NewBundleVariable(
				olmentity.NewBundleEntity(bundleSet["bundle-1"]),
				[]*olmentity.BundleEntity{
					olmentity.NewBundleEntity(bundleSet["bundle-6"]),
					olmentity.NewBundleEntity(bundleSet["bundle-7"]),
					olmentity.NewBundleEntity(bundleSet["bundle-8"]),
				},
			),
			olmvariables.NewBundleVariable(
				olmentity.NewBundleEntity(bundleSet["bundle-3"]),
				[]*olmentity.BundleEntity{},
			),
			olmvariables.NewBundleVariable(
				olmentity.NewBundleEntity(bundleSet["bundle-4"]),
				[]*olmentity.BundleEntity{},
			),
			olmvariables.NewBundleVariable(
				olmentity.NewBundleEntity(bundleSet["bundle-5"]),
				[]*olmentity.BundleEntity{},
			),
			olmvariables.NewBundleVariable(
				olmentity.NewBundleEntity(bundleSet["bundle-6"]),
				[]*olmentity.BundleEntity{},
			),
			olmvariables.NewBundleVariable(
				olmentity.NewBundleEntity(bundleSet["bundle-7"]),
				[]*olmentity.BundleEntity{
					olmentity.NewBundleEntity(bundleSet["bundle-8"]),
					olmentity.NewBundleEntity(bundleSet["bundle-9"]),
					olmentity.NewBundleEntity(bundleSet["bundle-10"]),
				},
			),
			olmvariables.NewBundleVariable(
				olmentity.NewBundleEntity(bundleSet["bundle-8"]),
				[]*olmentity.BundleEntity{},
			),
			olmvariables.NewBundleVariable(
				olmentity.NewBundleEntity(bundleSet["bundle-9"]),
				[]*olmentity.BundleEntity{},
			),
			olmvariables.NewBundleVariable(
				olmentity.NewBundleEntity(bundleSet["bundle-10"]),
				[]*olmentity.BundleEntity{},
			),
			olmvariables.NewBundleVariable(
				olmentity.NewBundleEntity(bundleSet["bundle-14"]),
				[]*olmentity.BundleEntity{},
			),
			olmvariables.NewBundleVariable(
				olmentity.NewBundleEntity(bundleSet["bundle-15"]),
				[]*olmentity.BundleEntity{},
			),
			olmvariables.NewBundleVariable(
				olmentity.NewBundleEntity(bundleSet["bundle-16"]),
				[]*olmentity.BundleEntity{},
			),
		}
		variables, err := crdConstraintVariableSource.GetVariables(ctx, entitySource)
		Expect(err).ToNot(HaveOccurred())
		// Note: When accounting for GVK Uniqueness (which we are currently not doing), we
		// would expect to have 26 variables from the 5 unique GVKs (Bar, Bit, Buz, Fiz, Foo).
		Expect(variables).To(HaveLen(21))
		var crdConstraintVariables []*olmvariables.BundleUniquenessVariable
		for _, variable := range variables {
			switch v := variable.(type) {
			case *olmvariables.BundleUniquenessVariable:
				crdConstraintVariables = append(crdConstraintVariables, v)
			}
		}
		// Note: As above, the 5 GVKs would appear here as GVK uniqueness constraints
		// if GVK Uniqueness were being accounted for.
		Expect(crdConstraintVariables).To(WithTransform(CollectGlobalConstraintVariableIDs, ConsistOf([]string{
			"another-package package uniqueness",
			"bar-package package uniqueness",
			"test-package-2 package uniqueness",
			"test-package package uniqueness",
			"some-package package uniqueness",
			"some-other-package package uniqueness",
		})))
	})

	It("should return an error if input variable source returns an error", func() {
		inputVariableSource = &MockInputVariableSource{Err: fmt.Errorf("error getting variables")}
		crdConstraintVariableSource = variablesources.NewCRDUniquenessConstraintsVariableSource(inputVariableSource)
		_, err := crdConstraintVariableSource.GetVariables(ctx, entitySource)
		Expect(err).To(HaveOccurred())
		Expect(err.Error()).To(ContainSubstring("error getting variables"))
	})
})

var _ input.EntitySource = &PanicEntitySource{}

type PanicEntitySource struct{}

func (p PanicEntitySource) Get(_ context.Context, _ deppy.Identifier) (*input.Entity, error) {
	return nil, fmt.Errorf("if you are seeing this it is because the global variable source is calling the entity source - this shouldn't happen")
}

func (p PanicEntitySource) Filter(_ context.Context, _ input.Predicate) (input.EntityList, error) {
	return nil, fmt.Errorf("if you are seeing this it is because the global variable source is calling the entity source - this shouldn't happen")
}

func (p PanicEntitySource) GroupBy(_ context.Context, _ input.GroupByFunction) (input.EntityListMap, error) {
	return nil, fmt.Errorf("if you are seeing this it is because the global variable source is calling the entity source - this shouldn't happen")
}

func (p PanicEntitySource) Iterate(_ context.Context, _ input.IteratorFunction) error {
	return fmt.Errorf("if you are seeing this it is because the global variable source is calling the entity source - this shouldn't happen")
}

type MockInputVariableSource struct {
	ResultSet []deppy.Variable
	Err       error
}

func (m *MockInputVariableSource) GetVariables(_ context.Context, _ input.EntitySource) ([]deppy.Variable, error) {
	if m.Err != nil {
		return nil, m.Err
	}
	return m.ResultSet, nil
}

func CollectGlobalConstraintVariableIDs(vars []*olmvariables.BundleUniquenessVariable) []string {
	ids := make([]string, 0, len(vars))
	for _, v := range vars {
		ids = append(ids, v.Identifier().String())
	}
	return ids
}
